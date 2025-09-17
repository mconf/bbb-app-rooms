# frozen_string_literal: true
require 'faraday'
require 'cgi'

module Moodle
  class API
    def self.create_calendar_event(moodle_token, sched_meeting_hash_id, scheduled_meeting, context_id, opts={})
      app_launch = AppLaunch.find_by(nonce: scheduled_meeting.created_by_launch_nonce)

      event_description = scheduled_meeting.description
      # Append the activity link to the event description
      if app_launch && app_launch.params['cmid']
        activity_url = URI.join(moodle_token.url, "/mod/lti/view.php?id=#{app_launch.params['cmid']}").to_s
        link_text = I18n.t('default.scheduled_meeting.calendar.description.link')
        link = "<a href=\"#{activity_url}\" target=\"_blank\">#{link_text}</a>"
        raw_string = "#{scheduled_meeting.description}\n#{link}"
        # Split each line into a paragraph
        event_description = raw_string.split("\n").compact_blank.map { |line| "<p>#{line}</p>" }.join
      end

      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_calendar_create_calendar_events',
        moodlewsrestformat: 'json',
        'events[0][name]' => scheduled_meeting.name,
        'events[0][description]' => event_description,
        'events[0][format]' => 1,
        'events[0][courseid]' => context_id,
        'events[0][timestart]' => scheduled_meeting.start_at.to_i,
        'events[0][timeduration]' => scheduled_meeting.duration,
        'events[0][visible]' => 1,
        'events[0][eventtype]' => 'course'
      }
      begin
        result = post(moodle_token.url, params)
      rescue Moodle::UrlNotFoundError, Moodle::TimeoutError, Moodle::RequestError
        return false
      end

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_calendar_create_calendar_events " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
        # The event fails to be created on Moodle if there is a "nopermissions" warning
        return false if result["warnings"].any? { |w| w["warningcode"] == "nopermissions" }
      end
      
      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return false
      else
        # Create a new Moodle Calendar Event
        event_params = { event_id: result["events"].first['id'],
                         scheduled_meeting_hash_id: sched_meeting_hash_id,
                         start_at: scheduled_meeting.start_at }
        MoodleCalendarEvent.create!(event_params)
      end

      Rails.logger.info(log_labels + "message=\"Event created on Moodle calendar: #{result}\"")

      true
    end

    def self.delete_calendar_event(moodle_token, event_id, context_id, opts)
      Rails.logger.info("[MOODLE API] Deleting event=`#{event_id}`")

      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_calendar_delete_calendar_events',
        moodlewsrestformat: 'json',
        'events[0][eventid]'=> event_id,
        'events[0][repeat]'=> 0,
      }
      begin
        result = post(moodle_token.url, params)
      rescue Moodle::UrlNotFoundError, Moodle::TimeoutError, Moodle::RequestError
        return false
      end

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_calendar_delete_calendar_events " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
        return false if result["warnings"].any? { |w| w["warningcode"] == "nopermissions" }
      end

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return false
      end

      Rails.logger.info(log_labels + "message=\"Event deleted on Moodle calendar: #{result}\"")

      true
    end

    def self.get_user_groups(moodle_token, user_id, context_id, opts={})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_group_get_course_user_groups',
        moodlewsrestformat: 'json',
        courseid: context_id,
        userid: user_id
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_group_get_course_user_groups " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return nil
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"User groups (userid #{user_id}, " \
                        "courseid #{context_id}): #{result['groups']}\"")

      result['groups']
    end

    def self.get_groupmode(moodle_token, resource_id, opts={})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_group_get_activity_groupmode',
        moodlewsrestformat: 'json',
        cmid: resource_id,
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_group_get_activity_groupmode " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result['exception'].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return nil
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"Activity groupmode (cmid #{resource_id}): #{result['groupmode']}" \
      " (0 for no groups, 1 for separate groups, 2 for visible groups)\"")

      result['groupmode']
    end

    def self.get_activity_data(moodle_token, instance_id, opts={})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_course_get_course_module_by_instance',
        moodlewsrestformat: 'json',
        module: 'lti',
        instance: instance_id,
      }
      result = post(moodle_token.url, params)
      
      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_course_get_course_module_by_instance " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"Activity with instance ID #{instance_id}: #{result}\"")
        return nil
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"Activity with instance ID #{instance_id}: #{result['cm']}\"")
      
      result['cm']
    end

    def self.get_course_groups(moodle_token, context_id, opts={})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_group_get_course_groups',
        moodlewsrestformat: 'json',
        courseid: context_id,
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_group_get_course_groups " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return nil
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"Course groups (courseid #{context_id}): #{result["body"]}\"")

      result["body"]
    end

    def self.get_course_attendance_instances(moodle_token, course_id, opts={})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_course_get_contents',
        moodlewsrestformat: 'json',
        courseid: course_id,
        'options[0][name]' => 'modname',
        'options[0][value]' => 'attendance'
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_course_get_contents " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"Failed to get course attendance instances: #{result}\"")
        return nil
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"Warnings while getting course attendance instances: #{result["warnings"].inspect}\"")
      end

      sections_data = result.is_a?(Array) ? result : result["body"]

      unless sections_data.is_a?(Array)
        Rails.logger.warn(log_labels + "message=\"Course contents data is not an array or is nil for courseid #{course_id}. Data: #{sections_data.inspect}\"")
        return []
      end

      attendance_instances = []
      sections_data.each do |section|
        unless section.is_a?(Hash) && section['modules'].is_a?(Array)
          Rails.logger.debug(log_labels + "message=\"Skipping malformed section: #{section.inspect}\"")
          next
        end

        section['modules'].each do |mod|
          attendance_instances << { instance: mod['instance'], name: mod['name'] }
        end
      end

      Rails.logger.info(log_labels + "message=\"Found attendance instances for courseid #{course_id}: #{attendance_instances.inspect}\"")
      attendance_instances
    end

    def self.token_functions_configured?(moodle_token, wsfunctions, opts={})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_webservice_get_site_info',
        moodlewsrestformat: 'json',
      }

      begin
        result = post(moodle_token.url, params)
      rescue Moodle::UrlNotFoundError, Moodle::TimeoutError, Moodle::RequestError
        return false
      end

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_webservice_get_site_info " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result['exception'].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return false
      end

      # Gets all registered function names
      function_names = result['functions'].map { |hash| hash['name'] }
      # Checks if every element of wsfunctions is listed on the function_names list
      missing_functions = wsfunctions - function_names

      if missing_functions.empty?
        Rails.logger.info(log_labels + "message=\"Every necessary " \
        "function is correctly configured in the Moodle Token service.\"")
        return true
      else
        Rails.logger.warn(log_labels + "message=\"The following functions are not configured " \
                           "in the Moodle Token service: #{missing_functions}.\"")
        return false
      end
    end

    def self.validate_token_and_check_missing_functions(moodle_token, wsfunctions, opts={})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_webservice_get_site_info',
        moodlewsrestformat: 'json',
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_webservice_get_site_info " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      validation_result = {}
      if result['exception'].present?
        # Checks for an error indicating that the configured token is invalid
        validation_result[:valid_token] = false if result['errorcode'] == 'invalidtoken'

        Rails.logger.error(log_labels + "message=\"#{result}\"")
        validation_result[:missing_functions] = wsfunctions

        return validation_result
      end

      # Gets all registered function names
      function_names = result['functions'].map { |hash| hash['name'] }
      # Checks if every element of wsfunctions is listed on the function_names list
      validation_result[:missing_functions] = wsfunctions - function_names

      if validation_result[:missing_functions].empty?
        Rails.logger.info(log_labels + "message=\"Every necessary " \
        "function is correctly configured in the Moodle Token service.\"")
      else
        Rails.logger.warn(log_labels + "message=\"The following functions are not configured " \
                           "in the Moodle Token service: #{validation_result[:missing_functions]}.\"")
      end

      validation_result
    end

    def self.add_attendance(moodle_token, courseid, name, intro = "", groupmode = 0, opts = {})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'mod_attendance_add_attendance',
        moodlewsrestformat: 'json',
        courseid: courseid,
        name: name,
        intro: intro,
        groupmode: groupmode
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=mod_attendance_add_attendance " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return false
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"Attendance instance created: #{result}\"")

      result['attendanceid']
    end

    def self.add_session(moodle_token, attendanceid, sessiontime, description = "", duration = 0, groupid = 0, addcalendarevent = 1, opts = {})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'mod_attendance_add_session',
        moodlewsrestformat: 'json',
        attendanceid: attendanceid,
        description: description,
        sessiontime: sessiontime,
        duration: duration,
        groupid: groupid,
        addcalendarevent: addcalendarevent 
      }

      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=mod_attendance_add_session " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return false
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"Attendance session created: #{result}\"")

      result['sessionid']
    end

    def self.get_session(moodle_token, sessionid, opts = {})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'mod_attendance_get_session',
        moodlewsrestformat: 'json',
        sessionid: sessionid
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=mod_attendance_get_session " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return nil
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"Attendance session data retrieved: #{result}\"")

      result
    end

    def self.get_session_statuses(moodle_token, sessionid, opts = {})
      session_data = get_session(moodle_token, sessionid, opts)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "wsfunction=mod_attendance_get_session (for statuses) " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}" # Note: duration is part of session_data

      unless session_data && session_data["statuses"].is_a?(Array)
        Rails.logger.error(log_labels + "message=\"Failed to retrieve statuses or statuses is not an array. Data: #{session_data.inspect}\"")
        return []
      end

      statuses_array = []
      session_data["statuses"].each do |status|
        if status.is_a?(Hash) && status.key?("id") && status.key?("description") && status.key?("grade")
          statuses_array << { id: status["id"], description: status["description"], grade: status["grade"] }
        else
          Rails.logger.warn(log_labels + "message=\"Skipping invalid status entry: #{status.inspect}\"")
        end
      end

      Rails.logger.info(log_labels + "message=\"Extracted session statuses: #{statuses_array.inspect}\"")
      statuses_array
    end

    def self.update_user_status(moodle_token, sessionid, studentid, takenbyid, statusid, statusset, opts = {})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'mod_attendance_update_user_status',
        moodlewsrestformat: 'json',
        sessionid: sessionid,
        studentid: studentid,
        takenbyid: takenbyid,
        statusid: statusid,
        statusset: statusset
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=mod_attendance_update_user_status " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return false
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"User status update result: #{result}\"")

      true
    end

    def self.get_enrolled_user_ids(moodle_token, courseid, opts = {})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_enrol_get_enrolled_users', # Changed endpoint
        moodlewsrestformat: 'json',
        courseid: courseid
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_enrol_get_enrolled_users " \
                    "courseid=#{courseid} " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return nil
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end

      users_data = result['body']
      unless users_data.is_a?(Array)
        Rails.logger.warn(log_labels + "message=\"Users data is not an array or is missing. Data: #{users_data.inspect}\"")
        return []
      end

      user_ids = users_data.map { |user| user['id'] }.compact
      Rails.logger.info(log_labels + "message=\"Retrieved #{user_ids.count} enrolled user IDs: #{user_ids.inspect}\"")

      user_ids
    end

    MAX_RETRIES = 3

    def self.post(host_url, params)
      retries ||= 0
      begin
        begin
          options = {
            headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
            request: { timeout: Rails.application.config.moodle_api_timeout },
            params: params
          }

          conn = Faraday.new(url: host_url, **options) do |config|
            config.response :json
            config.response :raise_error
            config.adapter :net_http
          end

          start_time = Time.now
          res = conn.post(host_url)
          duration = Time.now - start_time

          result = res.body.is_a?(Hash) ? res.body.merge({"duration" => duration}) :
                                          { "body" => res.body, "duration" => duration }

          Rails.logger.debug("[MOODLE API] Calling URL: #{host_url}?#{params.to_a.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')} | Moodle response: #{res.inspect}")
          return result

        rescue Faraday::ResourceNotFound => e
          Rails.logger.error( "[MOODLE API] url=#{host_url} " \
                              "duration=#{(Time.now - start_time).round(3)}s " \
                              "wsfunction=#{params[:wsfunction]} " \
                              "caller=#{caller(2..3)} " \
                              "message=\"Request failed (Faraday::ResourceNotFound): #{e}\" " \
                              "response_body=\"#{e.response_body&.gsub(/\n/, '')}\""
                            )
          raise UrlNotFoundError, e
        rescue Faraday::TimeoutError => e
          Rails.logger.error( "[MOODLE API] url=#{host_url} " \
                              "duration=#{(Time.now - start_time).round(3)}s " \
                              "wsfunction=#{params[:wsfunction]} " \
                              "caller=#{caller(2..3)} " \
                              "message=\"Request failed (Faraday::TimeoutError): #{e}\"")
          raise TimeoutError, e
        rescue Faraday::Error => e
          Rails.logger.error( "[MOODLE API] url=#{host_url} " \
                              "duration=#{(Time.now - start_time).round(3)}s " \
                              "wsfunction=#{params[:wsfunction]} " \
                              "caller=#{caller(2..3)} " \
                              "message=\"Request failed (Faraday::Error): #{e}\" " \
                              "response_body=\"#{e.response_body&.gsub(/\n/, '')}\""
                            )
          raise RequestError, e
        end
      rescue Moodle::UrlNotFoundError, Moodle::TimeoutError, Moodle::RequestError => e
        if (retries += 1) < MAX_RETRIES
          caller_name = params[:wsfunction] || 'Moodle::API.post'
          Rails.logger.warn "[#{caller_name}] Moodle API call failed (#{e.class}: #{e.message}), retrying (attempt #{retries + 1}/#{MAX_RETRIES})"
          sleep 1
          retry
        else
          caller_name = params[:wsfunction] || 'Moodle::API.post'
          Rails.logger.error "[#{caller_name}] Moodle API call failed after #{MAX_RETRIES} attempts (#{e.class}: #{e.message})."
          raise e
        end
      end
    end
  end

  class UrlNotFoundError < StandardError; end
  class TimeoutError < StandardError; end
  class RequestError < StandardError; end
end
