# frozen_string_literal: true
require 'faraday'

module Moodle
  class API
    def self.create_calendar_event(moodle_token, scheduled_meeting, context_id, opts={})
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_calendar_create_calendar_events',
        moodlewsrestformat: 'json',
        'events[0][name]' => scheduled_meeting.name,
        'events[0][description]' => scheduled_meeting.description,
        'events[0][format]' => 1,
        'events[0][courseid]' => context_id,
        'events[0][timestart]' => scheduled_meeting.start_at.to_i,
        'events[0][timeduration]' => scheduled_meeting.duration,
        'events[0][visible]' => 1,
        'events[0][eventtype]' => 'course'
      }
      result = post(moodle_token.url, params)

      log_labels =  "[MOODLE API] url=#{moodle_token.url} " \
                    "token_id=#{moodle_token.id} " \
                    "duration=#{result['duration']&.round(3)}s " \
                    "wsfunction=core_calendar_create_calendar_events " \
                    "#{('nonce=' + opts[:nonce].to_s + ' ') if opts[:nonce]}"

      if result["exception"].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return false
      else
        # Create a new Moodle Calendar Event
        event_params = { event_id: result["events"].first['id'],
                         scheduled_meeting_hash_id: scheduled_meeting.hash_id }
        puts("Event params: #{event_params.inspect}")
        MoodleCalendarEvent.create!(event_params)
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"Event created on Moodle calendar: #{result}\"")

      true
    end

    def self.generate_recurring_events(moodle_token, scheduled_meeting, context_id, opts)
      start_at = scheduled_meeting.start_at
      recurrence_type = scheduled_meeting.repeat
      defaut_period = Rails.application.config.moodle_recurring_events_month_period
      if recurrence_type == 'weekly'
        event_count = defaut_period*4
        cycle = 1
      else
        event_count = defaut_period*2
        cycle = 2
      end

      Rails.logger.info "Generating recurring events"
      recurring_events = []
      event_count.times do |i|
        next_start_at = start_at + (i * cycle).weeks
        recurring_events << ScheduledMeeting.new(
          hash_id: scheduled_meeting.hash_id,
          name: scheduled_meeting.name,
          description: scheduled_meeting.description,
          start_at: next_start_at,
          duration: scheduled_meeting.duration,
        )
      end
  
      Rails.logger.info "#{event_count} recurring events generated. Calling Moodle API create_calendar_event"
      recurring_events.each do |event|
        self.create_calendar_event(moodle_token, event, context_id, opts)
      end

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

    def self.token_functions_configured?(moodle_token, wsfunctions, opts={})
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

    def self.missing_token_functions(moodle_token, wsfunctions, opts={})
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

      if result['exception'].present?
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return wsfunctions
      end

      # Gets all registered function names
      function_names = result['functions'].map { |hash| hash['name'] }
      # Checks if every element of wsfunctions is listed on the function_names list
      missing_functions = wsfunctions - function_names

      if missing_functions.empty?
        Rails.logger.info(log_labels + "message=\"Every necessary " \
        "function is correctly configured in the Moodle Token service.\"")
      else
        Rails.logger.warn(log_labels + "message=\"The following functions are not configured " \
                           "in the Moodle Token service: #{missing_functions}.\"")
      end

      missing_functions
    end

    def self.valid_token?(moodle_token, opts={})
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

      if result['exception'].present? && result['errorcode'] == 'invalidtoken'
        Rails.logger.error(log_labels + "message=\"#{result}\"")
        return false
      else
        return true
      end
    end

    def self.post(host_url, params)
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

      res.body.is_a?(Hash) ? res.body.merge({"duration" => duration}) :
                             { "body" => res.body, "duration" => duration }

    rescue Faraday::ResourceNotFound => e
      Rails.logger.error( "[MOODLE API] url=#{host_url} " \
                          "duration=#{(Time.now - start_time).round(3)}s " \
                          "wsfunction=#{params[:wsfunction]} " \
                          "message=\"Request failed (Faraday::ResourceNotFound): #{e}\" " \
                          "response_body=\"#{e.response_body&.gsub(/\n/, '')}\""
                        )
      raise UrlNotFoundError, e
    rescue Faraday::TimeoutError => e
      Rails.logger.error( "[MOODLE API] url=#{host_url} " \
                          "duration=#{(Time.now - start_time).round(3)}s " \
                          "wsfunction=#{params[:wsfunction]} " \
                          "message=\"Request failed (Faraday::TimeoutError): #{e}\"")
      raise TimeoutError, e
    rescue Faraday::Error => e
      Rails.logger.error( "[MOODLE API] url=#{host_url} " \
                          "duration=#{(Time.now - start_time).round(3)}s " \
                          "wsfunction=#{params[:wsfunction]} " \
                          "message=\"Request failed (Faraday::Error): #{e}\" " \
                          "response_body=\"#{e.response_body&.gsub(/\n/, '')}\""
                        )
      raise RequestError, e
    end
  end

  class UrlNotFoundError < StandardError; end
  class TimeoutError < StandardError; end
  class RequestError < StandardError; end
end
