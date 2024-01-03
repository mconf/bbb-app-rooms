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

      if result["exception"].present?
        Rails.logger.error("[+++] MOODLE API EXCEPTION [+++] #{result["message"]}")
        return false
      end

      Rails.logger.info "[MOODLE API] Event created on Moodle calendar: #{result}"
      true
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
      end
    end
  end
end