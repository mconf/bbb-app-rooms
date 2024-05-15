# frozen_string_literal: true
require 'faraday'

module Moodle
  class API
    def self.create_calendar_event(moodle_token, scheduled_meeting, context_id)
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

      if result.nil? || result["exception"].present?
        Rails.logger.error("[MOODLE API - url: #{moodle_token.url}][EXCEPTION - core_calendar_create_calendar_events]: #{result}") unless result.nil?
        return false
      end
      Rails.logger.info "[MOODLE API - url: #{moodle_token.url}][INFO - core_calendar_create_calendar_events]: Event created on Moodle calendar: #{result}"

      true
    end

    def self.get_user_groups(moodle_token, user_id, context_id)
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_group_get_course_user_groups',
        moodlewsrestformat: 'json',
        courseid: context_id,
        userid: user_id
      }
      result = post(moodle_token.url, params)

      if result.nil? || result["exception"].present?
        Rails.logger.error("[MOODLE API - url: #{moodle_token.url}][EXCEPTION - core_group_get_course_user_groups]: #{result}") unless result.nil?
        return nil
      end
      # TO-DO: Investigar melhor os warnings e como tratá-los.
      if result["warnings"].present?
        Rails.logger.warn("[MOODLE API - url: #{moodle_token.url}][WARNING - core_group_get_course_user_groups]: #{result["warnings"].inspect}")
      end
      Rails.logger.info "[MOODLE API - url: #{moodle_token.url}][INFO - core_group_get_course_user_groups]: User groups (userid #{user_id}, courseid #{context_id}): #{result}"

      result['groups']
    end

    def self.get_groupmode(moodle_token, resource_id)
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_group_get_activity_groupmode',
        moodlewsrestformat: 'json',
        cmid: resource_id,
      }
      result = post(moodle_token.url, params)

      if result.nil? || result["exception"].present?
        Rails.logger.error("[MOODLE API - url: #{moodle_token.url}][EXCEPTION - core_group_get_activity_groupmode]: #{result}") unless result.nil?
        return nil
      end
      # TO-DO: Investigar melhor os warnings e como tratá-los.
      if result["warnings"].present?
        Rails.logger.warn("[MOODLE API - url: #{moodle_token.url}][WARNING - core_group_get_activity_groupmode]: #{result["warnings"].inspect}")
      end
      Rails.logger.info "[MOODLE API - url: #{moodle_token.url}][INFO - core_group_get_activity_groupmode]: Activity groupmode (cmid #{resource_id}): #{result}" \
      ' (0 for no groups, 1 for separate groups, 2 for visible groups)'

      result['groupmode']
    end

    def self.get_activity_data(moodle_token, instance_id)
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_course_get_course_module_by_instance',
        moodlewsrestformat: 'json',
        module: 'lti',
        instance: instance_id,
      }
      result = post(moodle_token.url, params)

      if result.nil? || result["exception"].present?
        Rails.logger.error("[MOODLE API - url: #{moodle_token.url}][EXCEPTION - core_course_get_course_module_by_instance]: Activity with instance id = #{instance_id} " \
                           "-> #{result}") unless result.nil?
        return nil
      end
      # TO-DO: Investigar melhor os warnings e como tratá-los.
      if result["warnings"].present?
        Rails.logger.warn("[MOODLE API - url: #{moodle_token.url}][WARNING - core_course_get_course_module_by_instance]: #{result["warnings"].inspect}")
      end
      Rails.logger.info "[MOODLE API - url: #{moodle_token.url}][INFO - core_course_get_course_module_by_instance]: Activity data (instance #{instance_id}): #{result}"
      
      result['cm']
    end

    def self.get_course_groups(moodle_token, context_id)
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_group_get_course_groups',
        moodlewsrestformat: 'json',
        courseid: context_id,
      }
      result = post(moodle_token.url, params)

      if result.nil? || (result.is_a?(Hash) && result["exception"].present?)
        Rails.logger.error("[MOODLE API - url: #{moodle_token.url}][EXCEPTION - core_group_get_course_groups]: #{result}") unless result.nil?
        return nil
      end
      # TO-DO: Investigar melhor os warnings e como tratá-los.
      if (result.is_a?(Hash) && result["warnings"]).present?
        Rails.logger.warn("[MOODLE API - url: #{moodle_token.url}][WARNING - core_group_get_course_groups]: #{result["warnings"].inspect}")
      end
      Rails.logger.info "[MOODLE API - url: #{moodle_token.url}][INFO - core_group_get_course_groups]: Course groups (courseid #{context_id}): #{result}"

      result
    end

    def self.check_token_functions(moodle_token, wsfunctions)
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_webservice_get_site_info',
        moodlewsrestformat: 'json',
      }
      result = post(moodle_token.url, params)
      return false if result.nil?

      if result["exception"].present?
        Rails.logger.error("[MOODLE API - url: #{moodle_token.url}][EXCEPTION - core_webservice_get_site_info]: #{result}")
        return false
      end

      # Gets all registered function names
      function_names = result["functions"].map { |hash| hash["name"] }
      # Checks if every element of wsfunctions is listed on the function_names list
      missing_functions = wsfunctions - function_names

      if missing_functions.empty?
        Rails.logger.info "[MOODLE API - url: #{moodle_token.url}][INFO - core_webservice_get_site_info]: Every necessary " \
        "function is correctly configured in the Moodle Token service."
        return true
      else
        Rails.logger.error("[MOODLE API - url: #{moodle_token.url}][EXCEPTION - core_webservice_get_site_info] The following " \
                           "functions are not configured in the Moodle Token service: #{missing_functions}.")
        return false
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

      res.body.is_a?(Hash) ? res.body.merge({duration: duration}) : { body: res.body, duration: duration }
    rescue Faraday::ResourceNotFound => e
      Rails.logger.error("[MOODLE API - POST #{host_url}, duration: #{(Time.now - start_time).round(3)}s][#{params[:wsfunction]}] request failed (Faraday::ResourceNotFound): #{e}")
      raise UrlNotFoundError, e
    rescue Faraday::Error => e
      Rails.logger.error("[MOODLE API - POST #{host_url}, duration: #{(Time.now - start_time).round(3)}s][#{params[:wsfunction]}] request failed (Faraday::Error): #{e}")
      raise RequestError, e
    end
  end

  class UrlNotFoundError < StandardError; end
  class RequestError < StandardError; end
end
