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
      end

      if result["warnings"].present?
        Rails.logger.warn(log_labels + "message=\"#{result["warnings"].inspect}\"")
      end
      Rails.logger.info(log_labels + "message=\"Event created on Moodle calendar: #{result}\"")

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
