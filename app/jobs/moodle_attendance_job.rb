# frozen_string_literal: true

require 'time' # Required for Time.parse

class MoodleAttendanceJob < ApplicationJob
  queue_as :default
  include ApplicationHelper

  def perform(conference_data_json, theme, locale)
    conference_data = JSON.parse(conference_data_json)

    # --- Derive IDs from conference_data ---
    # 1. Get scheduled_meeting_id
    scheduled_meeting_id = conference_data.dig('data', 'metadata', 'bbb_meeting_db_id')
    unless scheduled_meeting_id
      Rails.logger.error "MoodleAttendanceJob: Could not find 'bbb_meeting_db_id' in conference_data metadata."
      return
    end
    scheduled_meeting = ScheduledMeeting.find_by(id: scheduled_meeting_id)
    unless scheduled_meeting
      Rails.logger.error "MoodleAttendanceJob: Could not find ScheduledMeeting with ID #{scheduled_meeting_id} (from bbb_meeting_db_id)."
      return
    end

    # 2. Get AppLaunch and app_launch_id
    launch_nonce = conference_data.dig('data', 'metadata', 'bbb_launch_nonce')
    unless launch_nonce
      Rails.logger.error "MoodleAttendanceJob: Could not find 'bbb_launch_nonce' in conference_data metadata."
      return
    end
    app_launch = AppLaunch.find_by(nonce: launch_nonce)
    unless app_launch
      Rails.logger.error "MoodleAttendanceJob: Could not find AppLaunch with nonce '#{launch_nonce}' (from bbb_launch_nonce)."
      return
    end

    # 3. Get MoodleToken and moodle_token_id
    oauth_consumer_key = conference_data.dig('data', 'metadata', 'bbb_oauth_consumer_key')
    unless oauth_consumer_key
      Rails.logger.error "MoodleAttendanceJob: Could not find 'bbb_oauth_consumer_key' in conference_data metadata."
      return
    end
    consumer_config = ConsumerConfig.find_by(key: oauth_consumer_key)
    unless consumer_config
      Rails.logger.error "MoodleAttendanceJob: Could not find ConsumerConfig with key '#{oauth_consumer_key}' (from bbb_oauth_consumer_key)."
      return
    end
    moodle_token = MoodleToken.find_by(consumer_config_id: consumer_config.id)
    unless moodle_token
      Rails.logger.error "MoodleAttendanceJob: Could not find MoodleToken for ConsumerConfig ID #{consumer_config.id}."
      return
    end

    Rails.logger.info "MoodleAttendanceJob: Successfully derived IDs - MoodleToken: #{moodle_token.id}, ScheduledMeeting: #{scheduled_meeting.id}, AppLaunch: #{app_launch.id}."
    # --- End of ID derivation ---

    unless moodle_token.url.present? && moodle_token.token.present?
      Rails.logger.error "MoodleAttendanceJob: MoodleToken #{moodle_token.id} is missing URL or token."
      return
    end

    group_select_enabled = moodle_token&.group_select_enabled?
    course_id = app_launch.context_id
    
    # 1. Get or Create Attendance ID
    attendance_id = get_or_create_moodle_attendance(moodle_token, course_id, group_select_enabled, locale)
    return unless attendance_id

    # 2. Create Session
    session_id = create_moodle_session(moodle_token, attendance_id, scheduled_meeting, conference_data, app_launch, group_select_enabled, theme, locale)
    return unless session_id

    # 3. Get status ids
    status_ids = get_presence_and_absence_status_ids(moodle_token, session_id)
    presence_status_id = status_ids[:presence_status_id]
    absence_status_id = status_ids[:absence_status_id]

    unless presence_status_id && absence_status_id
      error_message = "MoodleAttendanceJob: Could not retrieve valid status IDs. "
      error_message += "presence_status_id is missing. " unless presence_status_id
      error_message += "absence_status_id is missing. " unless absence_status_id
      error_message += "Aborting attendance marking."
      Rails.logger.error error_message
      return
    end

    # 4. Mark Attendance for Users
    mark_attendance_for_users(moodle_token, session_id, presence_status_id, absence_status_id, conference_data, course_id)

    Rails.logger.info "MoodleAttendanceJob: Finished processing for scheduled_meeting #{scheduled_meeting.id}."
  end

  private

  MAX_RETRIES = 3 # Define the maximum number of retries

  def with_retries
    begin
      retries ||= 0
      yield
    rescue Moodle::UrlNotFoundError, Moodle::TimeoutError, Moodle::RequestError => e
      if (retries += 1) < MAX_RETRIES
        Rails.logger.warn "MoodleAttendanceJob: API call failed (#{e.class}: #{e.message}), retrying (attempt #{retries + 1}/#{MAX_RETRIES})"
        sleep 1
        retry
      else
        Rails.logger.error "MoodleAttendanceJob: API call failed after #{MAX_RETRIES} attempts (#{e.class}: #{e.message})."
        raise e # Re-raise the exception to let the job fail
      end
    end
  end

  def get_or_create_moodle_attendance(moodle_token, course_id, group_select_enabled, locale)
    existing_attendances = with_retries { Moodle::API.get_course_attendance_instances(moodle_token, course_id) }

    if existing_attendances.nil?
      Rails.logger.error "MoodleAttendanceJob: Moodle::API.get_course_attendance_instances returned nil (API error). Cannot proceed to find or create attendance for course_id #{course_id}."
      return nil
    end

    if existing_attendances.is_a?(Array)
      if existing_attendances.any?
        first_attendance = existing_attendances.first

        if first_attendance.is_a?(Hash) && first_attendance.key?(:instance) && !first_attendance[:instance].nil?
          attendance_id = first_attendance[:instance].to_i
          Rails.logger.info "MoodleAttendanceJob: Found existing Moodle attendance. Using the first one with ID: #{attendance_id} (Name: '#{first_attendance[:name]}') for course_id #{course_id}."
          return attendance_id
        else
          Rails.logger.warn "MoodleAttendanceJob: Existing attendance instances found for course_id #{course_id}, but the first entry is malformed or missing a valid 'instance' key: #{first_attendance.inspect}."
          return nil 
        end
      else
        Rails.logger.info "MoodleAttendanceJob: No existing attendance instances found for course_id #{course_id} (API returned empty array). Creating new one."
        
        target_attendance_name = I18n.t('jobs.moodle_attendance.attendance_name', locale: locale)
        group_mode_param = group_select_enabled ? 1 : 0 # 0: no groups, 1: separate groups, 2: visible
        
        new_attendance_id = with_retries do
          Moodle::API.add_attendance(
            moodle_token,
            course_id,
            target_attendance_name,
            "", # intro
            group_mode_param
          )
        end
        unless new_attendance_id
          Rails.logger.error "MoodleAttendanceJob: Failed to create Moodle attendance for course_id #{course_id} with name '#{target_attendance_name}'."
          return nil
        end
        Rails.logger.info "MoodleAttendanceJob: Created Moodle attendance with ID: #{new_attendance_id} for course_id #{course_id}."
        return new_attendance_id
      end
    else # Not nil and not an Array
      Rails.logger.error "MoodleAttendanceJob: Moodle::API.get_course_attendance_instances returned an unexpected type: #{existing_attendances.class} for course_id #{course_id}. Response: #{existing_attendances.inspect}. Cannot proceed."
      return nil
    end
  end

  def create_moodle_session(moodle_token, attendance_id, scheduled_meeting, conference_data, app_launch, group_select_enabled, theme, locale)
    current_consumer_config = moodle_token.consumer_config
    theme_display_name = case theme
                         when 'rnp'
                           'ConferênciaWeb'
                         when 'elos'
                           'Elos'
                          else
                            theme # Fallback to the raw theme name
                         end

    session_description = "<p>#{scheduled_meeting.meeting_name}</p> " \
    "#{'<p>' + scheduled_meeting.description + '</p>' || ''} " \
    "#{'<p>' + scheduled_meeting.start_at_date(locale) + ', ' + scheduled_meeting.start_at_time(locale) + '</p>' || ''} " \
    "<p><em>#{I18n.t('jobs.moodle_attendance.session_description_footer', app_theme: theme_display_name, locale: locale)}</em></p>"

    start_time_str = conference_data.dig('data', 'start')
    begin
      parsed_start_time = Time.parse(start_time_str)
    rescue ArgumentError => e
      Rails.logger.error "MoodleAttendanceJob: Invalid start_time format '#{start_time_str}': #{e.message}"
      return
    end
    session_time_unix = parsed_start_time.to_i
    session_duration_seconds = conference_data.dig('data', 'duration').to_i

    session_group_id = 0
    if group_select_enabled
      moodle_group_id_param = scheduled_meeting.moodle_group_id
      session_group_id = moodle_group_id_param.to_i if moodle_group_id_param.present?
      Rails.logger.info "MoodleAttendanceJob: group_select_enabled is true. Using moodle_group_id: #{session_group_id} (from custom_param 'moodle_group_id': #{moodle_group_id_param})."
    end
    
    session_id = with_retries do
      Moodle::API.add_session(
        moodle_token,
        attendance_id,
        session_time_unix,
        session_description,
        session_duration_seconds,
        session_group_id,
        0 # addcalendarevent = 0
      )
    end

    unless session_id
      Rails.logger.error "MoodleAttendanceJob: Failed to create Moodle session for attendance_id #{attendance_id}."
      return nil
    end
    Rails.logger.info "MoodleAttendanceJob: Created Moodle session with ID: #{session_id} ---- #{session_id.inspect}."
    session_id
  end

  def get_presence_and_absence_status_ids(moodle_token, session_id)
    session_statuses = with_retries { Moodle::API.get_session_statuses(moodle_token, session_id) }
    
    unless session_statuses.is_a?(Array) && session_statuses.any?
      Rails.logger.error "MoodleAttendanceJob: Failed to retrieve session statuses or no statuses found for session ID #{session_id}. API returned: #{session_statuses.inspect}"
      return { presence_status_id: nil, absence_status_id: nil }
    end

    # Ensure all statuses have a grade for comparison, defaulting to 0 if missing or not a number
    # and convert grade to float for proper comparison.
    valid_statuses = session_statuses.select { |s| s.is_a?(Hash) && s.key?(:id) && s.key?(:grade) }
                                     .map { |s| s.merge(grade: s[:grade].to_f) }

    if valid_statuses.empty?
      Rails.logger.error "MoodleAttendanceJob: No valid statuses with ID and grade found for session ID #{session_id}. Original statuses: #{session_statuses.inspect}"
      return { presence_status_id: nil, absence_status_id: nil }
    end

    highest_grade_status = valid_statuses.max_by { |status| status[:grade] }
    lowest_grade_status = valid_statuses.min_by { |status| status[:grade] }
    
    presence_status_id = highest_grade_status ? highest_grade_status[:id] : nil
    absence_status_id = lowest_grade_status ? lowest_grade_status[:id] : nil

    if presence_status_id.nil? || absence_status_id.nil?
      Rails.logger.error "MoodleAttendanceJob: Could not determine status IDs for presence and/or absence for session ID #{session_id}. Valid statuses: #{valid_statuses.inspect}"
    else
      Rails.logger.info "MoodleAttendanceJob: For session ID #{session_id} - Presence status ID: #{presence_status_id} (Grade: #{highest_grade_status[:grade]}), Absence status ID: #{absence_status_id} (Grade: #{lowest_grade_status[:grade]})."
    end
    
    { presence_status_id: presence_status_id, absence_status_id: absence_status_id }
  end

  def mark_attendance_for_users(moodle_token, session_id, presence_status_id, absence_status_id, conference_data, course_id)
    conference_attendees_data = conference_data.dig('data', 'attendees')
    unless conference_attendees_data.is_a?(Array)
      Rails.logger.error "MoodleAttendanceJob: Conference attendees data is missing or not an array."
      return
    end

    first_moderator = conference_attendees_data.find { |att| att['moderator'] == true }
    unless first_moderator && first_moderator['ext_user_id'].present?
      Rails.logger.error "MoodleAttendanceJob: Could not find a moderator with ext_user_id to use as 'takenbyid'."
      return
    end
    taken_by_id = first_moderator['ext_user_id']
    Rails.logger.info "MoodleAttendanceJob: Using moderator ext_user_id #{taken_by_id} as takenbyid for session ID #{session_id}."

    status_set_param = 0

    present_user_ids = conference_attendees_data.map { |att| att['ext_user_id']&.to_i }.compact.uniq
    Rails.logger.info "MoodleAttendanceJob: User IDs from conference data (present): #{present_user_ids.inspect} for session ID #{session_id}."

    present_marked_count = 0
    present_failed_count = 0
    
    present_user_ids.each do |student_id|
      success = with_retries do
        Moodle::API.update_user_status(
          moodle_token, session_id, student_id, taken_by_id, presence_status_id, status_set_param
        )
      end
      if success
        Rails.logger.info "MoodleAttendanceJob: Successfully marked PRESENT for student ID #{student_id} in session ID #{session_id}."
        present_marked_count += 1
      else
        Rails.logger.error "MoodleAttendanceJob: Failed to mark PRESENT for student ID #{student_id} in session ID #{session_id}."
        present_failed_count += 1
      end
    end

    absent_marked_count = 0
    absent_failed_count = 0
    
    all_moodle_user_ids = with_retries { Moodle::API.get_enrolled_user_ids(moodle_token, course_id) }

    if all_moodle_user_ids.nil?
      Rails.logger.error "MoodleAttendanceJob: Failed to retrieve enrolled users from Moodle for course ID #{course_id}. Cannot mark absent users for session ID #{session_id}."
    else
      Rails.logger.info "MoodleAttendanceJob: All enrolled Moodle user IDs for course #{course_id}: #{all_moodle_user_ids.inspect}."
      absent_user_ids = all_moodle_user_ids - present_user_ids
      Rails.logger.info "MoodleAttendanceJob: User IDs to be marked ABSENT: #{absent_user_ids.inspect} for session ID #{session_id}."

      absent_user_ids.each do |student_id|
        success = with_retries do
          Moodle::API.update_user_status(
            moodle_token, session_id, student_id, taken_by_id, absence_status_id, status_set_param
          )
        end
        if success
          Rails.logger.info "MoodleAttendanceJob: Successfully marked ABSENT for student ID #{student_id} in session ID #{session_id}."
          absent_marked_count += 1
        else
          Rails.logger.error "MoodleAttendanceJob: Failed to mark ABSENT for student ID #{student_id} in session ID #{session_id}."
          absent_failed_count += 1
        end
      end
    end

    Rails.logger.info "MoodleAttendanceJob: Attendance marking summary for session ID #{session_id} - Present (Success: #{present_marked_count}, Failed: #{present_failed_count}), Absent (Success: #{absent_marked_count}, Failed: #{absent_failed_count})."
  end
end
