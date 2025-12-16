require 'time' # for Time.parse

class BrightspaceAttendanceJob < ApplicationJob
  queue_as :default
  include ApplicationHelper

  def perform(conference_data_json, locale)
    ### parse meeting data JSON
    begin
      conference_data = JSON.parse(conference_data_json)
    rescue JSON::ParserError => e
      Resque.logger.error "[BrightspaceAttendanceJob] Failed to parse JSON from meeting data: #{e.message}"
      return
    end

    ### find ScheduledMeeting and AppLaunch
    scheduled_meeting = find_scheduled_meeting(conference_data)
    return unless scheduled_meeting
    app_launch = find_app_launch(conference_data)
    return unless app_launch
    Resque.logger.info "[BrightspaceAttendanceJob] User info from app_launch: " \
    "email=#{app_launch.user_params[:email]}, uid=#{app_launch.user_params[:uid]}, roles=#{app_launch.user_params[:roles]}"

    ### prepare Brightspace client
    base_url = app_launch.brightspace_oauth.url
    # the access token used to authenticate the calls to Brightspace API is taken from the user
    # who first started the meeting (usually the instructor), and such token must have the necessary
    # scopes to manage grades and read enrollments. It is expected to be stored in the omniauth_auth
    # credentials, in the user's app_launch, after OAuth authentication
    access_token = app_launch.omniauth_auth.dig('brightspace','credentials', 'token')
    brightspace_client = Mconf::BrightspaceClient.new(base_url, access_token, logger: Resque.logger)

    I18n.with_locale(locale) do
      ### get (or create) the grade category reserved for attendances
      # this category groups all grade objects created for attendance marking
      categories = brightspace_client.get_course_grade_categories(app_launch.context_id)
      Resque.logger.info "[BrightspaceAttendanceJob] Grade categories from course '#{app_launch.context_id}':" \
      " #{categories.map { |c| c['Name'] }}"
      # the category is expected to have a specific name defined in environment variable
      attendance_category_name = Mconf::Env.fetch('BRIGHTSPACE_ATTENDANCE_CATEGORY_NAME', 'Presença nas aulas online')
      attendance_category = categories&.find { |category| category['Name'] == attendance_category_name }
      if attendance_category.nil?
        # if not found, create the category
        Resque.logger.info "[BrightspaceAttendanceJob] Grade category for attendances not found, creating one"
        attendance_category = brightspace_client.create_course_grade_category(
          app_launch.context_id,
          name: attendance_category_name,
          short_name: attendance_category_name
        )
        if attendance_category.nil?
          # in the rare case the category could not be created, log a warning and proceed without it
          # grade objects can still be created without a category
          Resque.logger.warn "[BrightspaceAttendanceJob] Failed to create grade category for attendances, proceeding without it"
          attendance_category = { 'Id' => nil }
        else
          Resque.logger.info "[BrightspaceAttendanceJob] Grade category created: #{attendance_category}"
        end
      else
        Resque.logger.info "[BrightspaceAttendanceJob] Grade category for attendances found, id=#{attendance_category['Id']}"
      end

      ### create a Grade Object to register attendances for this meeting
      start_time_str = conference_data.dig('data', 'start')
      begin
        parsed_start_time = Time.parse(start_time_str)
      rescue ArgumentError => e
        Resque.logger.warn "[BrightspaceAttendanceJob] Invalid start_time format '#{start_time_str}': #{e.message}." \
        "Using scheduled_meeting start date (#{scheduled_meeting.start_at_date(locale)}) instead"
        parsed_start_time = scheduled_meeting.start_at_date(locale)
      end
      meeting_date = I18n.l(parsed_start_time, format: :short_custom).gsub('/', '-')
      grade_name = "Presença #{meeting_date}"
      grade_object = brightspace_client.create_grade_object(
        app_launch.context_id,
        attendance_category['Id'],
        name: grade_name,
        short_name: meeting_date
      )
      if grade_object.nil?
        Resque.logger.error "[BrightspaceAttendanceJob] Grade Object '#{grade_name}' could not be created, aborting job"
        return
      end
      Resque.logger.info "[BrightspaceAttendanceJob] Grade Object created: #{grade_object}"

      ### retrieve the conference attendees
      conference_attendees_data = conference_data.dig('data', 'attendees')
      unless conference_attendees_data.is_a?(Array)
        Resque.logger.error "[BrightspaceAttendanceJob] Conference attendees data is missing or not an array."
        return
      end
      # User IDs sent by Brightspace on LTI launches have the format "<random-string>_123", where 123 is the 'Identifier'
      # used internally, so we extract the numeric ID part
      present_user_ids = conference_attendees_data.map { |att| att['ext_user_id']&.split('_')&.last&.to_i }.compact.uniq
      # remove the current user (instructor) from the list of present students
      present_user_ids.delete(app_launch.user_params[:uid].split('_').last.to_i)
      Resque.logger.info "[BrightspaceAttendanceJob] User IDs from conference data (present): #{present_user_ids.inspect}"

      ### update grade value for each conference attendee
      present_marked_count = 0
      present_failed_count = 0
      present_user_ids.each do |student_id|
        success = brightspace_client.update_grade_value(
          app_launch.context_id,
          grade_object_id: grade_object['Id'],
          user_id: student_id,
          grade_value: 10
        )
        if success
          Resque.logger.info "[BrightspaceAttendanceJob] Successfully assigned grade 10 to student ID #{student_id}"
          present_marked_count += 1
        else
          Resque.logger.error "[BrightspaceAttendanceJob] Failed to assign grade 10 to student ID #{student_id}"
          present_failed_count += 1
        end
      end

      ### retrieve the IDs of all enrolled users in the course
      enrollments_first_page = brightspace_client.get_course_users(app_launch.context_id)
      if enrollments_first_page.present? && enrollments_first_page['Objects']
        Resque.logger.info "[BrightspaceAttendanceJob] Retrieved first page of enrolled users from course ID #{app_launch.context_id}"
        all_enrolled_user_ids = enrollments_first_page['Objects'].map { |user| user['Identifier'].to_i }

        # check if there are more pages to retrieve
        if enrollments_first_page['Next'].present?
          Resque.logger.info "[BrightspaceAttendanceJob] More enrolled users available, retrieving all pages"
          next_page_url = enrollments_first_page['Next']
          while next_page_url
            page = brightspace_client.get_course_users(app_launch.context_id, next_page_url: next_page_url)
            if page && page['Objects']
              all_enrolled_user_ids.concat(page['Objects'].map { |user| user['Identifier'].to_i })
              next_page_url = page['Next']
              Resque.logger.info "[BrightspaceAttendanceJob] Retrieved a page of enrolled users, next page URL: #{next_page_url}"
            else
              Resque.logger.error "[BrightspaceAttendanceJob] Failed to retrieve a page of enrolled users, stopping pagination"
              break
            end
          end
        end
        Resque.logger.info "[BrightspaceAttendanceJob] All enrolled user IDs from course #{app_launch.context_id}:" \
        " #{all_enrolled_user_ids.inspect}"

        ### assign grade 0 for each enrolled user not present in the meeting
        absent_user_ids = all_enrolled_user_ids - present_user_ids
        Resque.logger.info "[BrightspaceAttendanceJob] User IDs to be assigned grade 0: #{absent_user_ids.inspect}"
        absent_marked_count = 0
        absent_failed_count = 0
        absent_user_ids.each do |student_id|
          success = brightspace_client.update_grade_value(
            app_launch.context_id,
            grade_object_id: grade_object['Id'],
            user_id: student_id,
            grade_value: 0
          )
          if success
            Resque.logger.info "[BrightspaceAttendanceJob] Successfully assigned grade 0 to student ID #{student_id}"
            absent_marked_count += 1
          else
            Resque.logger.error "[BrightspaceAttendanceJob] Failed to assign grade 0 to student ID #{student_id}"
            absent_failed_count += 1
          end
        end
      # no enrolled users retrieved
      else
        Resque.logger.error "[BrightspaceAttendanceJob] Failed to retrieve enrolled users from course ID #{app_launch.context_id}." \
        " It will not be possible to assign grade 0 to absent students"
      end

      total_count = present_user_ids.size + absent_user_ids.size
      Resque.logger.info "[BrightspaceAttendanceJob] Attendance marking summary for scheduled_meeting '#{scheduled_meeting.name}'" \
      " - Total = #{total_count}, Present (success=#{present_marked_count}, failed=#{present_failed_count})," \
      " Absent (success=#{absent_marked_count}, failed=#{absent_failed_count})."
    end
  end

  private

  # @param conference_data [Hash]
  # @return [ScheduledMeeting, nil]
  def find_scheduled_meeting(conference_data)
    scheduled_meeting_id = conference_data.dig('data', 'metadata', 'bbb_meeting_db_id')
    unless scheduled_meeting_id
      Resque.logger.error "[BrightspaceAttendanceJob] Could not find 'bbb_meeting_db_id' in conference_data metadata."
      return nil
    end
    Resque.logger.info "[BrightspaceAttendanceJob] Successfully derived ScheduledMeeting id=#{scheduled_meeting_id}"

    scheduled_meeting = ScheduledMeeting.find_by(id: scheduled_meeting_id)
    unless scheduled_meeting
      Resque.logger.error "[BrightspaceAttendanceJob] Could not find ScheduledMeeting with ID #{scheduled_meeting_id}" \
      " (from bbb_meeting_db_id)."
      return nil
    end
    Resque.logger.info "[BrightspaceAttendanceJob] ScheduledMeeting found, name=#{scheduled_meeting.name}"

    scheduled_meeting
  end

  # @param conference_data [Hash]
  # @return [AppLaunch, nil]
  def find_app_launch(conference_data)
    launch_nonce = conference_data.dig('data', 'metadata', 'bbb_launch_nonce')
    unless launch_nonce
      Resque.logger.error "[BrightspaceAttendanceJob] Could not find 'bbb_launch_nonce' in conference_data metadata."
      return nil
    end
    Resque.logger.info "[BrightspaceAttendanceJob] Successfully derived AppLaunch nonce=#{launch_nonce}"

    app_launch = AppLaunch.find_by(nonce: launch_nonce)
    unless app_launch
      Resque.logger.error "[BrightspaceAttendanceJob] Could not find AppLaunch with nonce '#{launch_nonce}'" \
      " (from bbb_launch_nonce)."
      return nil
    end

    app_launch
  end
end
