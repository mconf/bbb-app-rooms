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
        Rails.logger.error("[+++] MOODLE API EXCEPTION [+++] #{result["message"]}") unless result.nil?
        return false
      end

      Rails.logger.info "[MOODLE API] Event created on Moodle calendar: #{result}"
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
        Rails.logger.error("[+++] MOODLE API EXCEPTION [+++] #{result["message"]}") unless result.nil?
        return nil
      end

      # TO-DO: Investigar melhor os warnings e como tratá-los.
      if result["warnings"].present?
        Rails.logger.warn("[+++] MOODLE API WARNING [+++] #{result["warnings"].inspect}")
      end

      Rails.logger.info "[MOODLE API] User groups: #{result}"
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
        Rails.logger.error("[+++] MOODLE API EXCEPTION [+++] #{result["message"]}") unless result.nil?
        return nil
      end

      # TO-DO: Investigar melhor os warnings e como tratá-los.
      if result["warnings"].present?
        Rails.logger.warn("[+++] MOODLE API WARNING [+++] #{result["warnings"].inspect}")
      end

      Rails.logger.info "[MOODLE API] Activity #{resource_id} groupmode: #{result}"
      
      # 0 for no groups, 1 for separate groups, 2 for visible groups
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
        Rails.logger.error("[+++] MOODLE API EXCEPTION [+++] #{result["message"]}") unless result.nil?
        return nil
      end

      # TO-DO: Investigar melhor os warnings e como tratá-los.
      if result["warnings"].present?
        Rails.logger.warn("[+++] MOODLE API WARNING [+++] #{result["warnings"].inspect}")
      end

      Rails.logger.info "[MOODLE API] Activity #{instance_id} data: #{result}"
      
      result['cm']
    end

    def self.get_course_groups(moodle_token, context_id)
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_group_get_groups_for_selector',
        moodlewsrestformat: 'json',
        courseid: context_id,
      }

      result = post(moodle_token.url, params)

      if result.nil? || result["exception"].present?
        Rails.logger.error("[+++] MOODLE API EXCEPTION [+++] #{result["message"]}") unless result.nil?
        return nil
      end

      # TO-DO: Investigar melhor os warnings e como tratá-los.
      if result["warnings"].present?
        Rails.logger.warn("[+++] MOODLE API WARNING [+++] #{result["warnings"].inspect}")
      end

      Rails.logger.info "[MOODLE API] Activity #{context_id} groupmode: #{result}"
      
      # 0 for no groups, 1 for separate groups, 2 for visible groups
      result["groups"]
    end

    def self.check_token_functions(moodle_token, wsfunction)
      params = {
        wstoken: moodle_token.token,
        wsfunction: 'core_webservice_get_site_info',
        moodlewsrestformat: 'json',
      }

      result = post(moodle_token.url, params)
      return false if result.nil?

      if result["exception"].present?
        Rails.logger.error("[+++] MOODLE API EXCEPTION [+++] #{result["message"]}")
        return false
      end

      result["functions"].any? { |hash| hash["name"] == wsfunction }
    end


    def self.post(host_url, params)
      begin
        headers = {'Content-Type': 'application/x-www-form-urlencoded'}
        response = Faraday.post(host_url, params, headers)

        JSON.parse(response.body)
      rescue Faraday::Error => e
        Rails.logger.error("Connection to Moodle API failed: #{e}")
        return nil
      end
    end
  end
end

# wstoken: ed3e45f150f3a15488ee9f60dad338ac
# wsfunction: core_calendar_create_calendar_events
# moodlewsrestformat: json
# events[0][name]: name
# events[0][description]: description
# events[0][format]: 1
# events[0][courseid]: 7
# events[0][timestart]: 122121
# events[0][timeduration]: 12121
# events[0][visible]: 1
# events[0][eventtype]: course

# core_group_get_groups: retorna dados de uma lista de grupos (groupIdList) -> nao precisa, a de baixo ja retorna os nomes
# core_group_get_course_user_groups: grupos que o boneco participa ()
# wstoken:ed3e45f150f3a15488ee9f60dad338ac
# wsfunction:core_group_get_course_user_groups
# moodlewsrestformat:json
# courseid:7
# userid:13