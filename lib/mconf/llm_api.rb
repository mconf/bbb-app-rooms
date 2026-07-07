module Mconf
  class LlmApi
    class ApiUrlMissingError < StandardError; end

    # Request both AI artifacts (ai_summary and transcription) for a meeting as a unified request
    def self.request_ai_artifacts(internal_meeting_id)
      check_api_url
      return nil if internal_meeting_id.blank?

      # `script_name` blank prevents '/rooms' from being prepended twice in the url
      callback_url = Rails.application.routes.url_helpers.ai_artifacts_url(
        host: Rails.application.config.url_host, protocol: 'https', script_name: ''
      )

      Rails.logger.info "[LLM API] Requesting AI artifacts (ai_summary + transcription) for internalMeetingID='#{internal_meeting_id}'"

      response = connection.post('/request_artifacts') do |req|
        req.body = { internal_meeting_id: internal_meeting_id, callback_url: callback_url }
      end

      if response.body["error"].present?
        Rails.logger.error "[LLM API] (#{response.status}) Error requesting AI artifacts: #{response.body}"
      else
        Rails.logger.info "[LLM API] AI artifacts successfully requested: (#{response.status}) #{response.body}"
      end

      response
    end

    private

    def self.connection
      Faraday.new(url: Rails.application.config.llm_api_url) do |f|
        f.request :json
        f.response :json
      end
    end

    # Raises ApiUrlMissingError if the API URL is missing from the application config
    def self.check_api_url
      raise ApiUrlMissingError, '[LLM API] URL config is missing.' if Rails.application.config.llm_api_url.blank?
    end
  end
end
