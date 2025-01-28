module Mconf
  class DataApi
    class ApiUrlMissingError < StandardError; end

    # Calls the API to get the link for artifacts of given month
    # Returns a hash with the links from the API's response
    #
    # @return [Hash] with 2 keys: csv and xls
    def self.get_report_artifacts(guid, date, locale = 'pt')
      check_api_url

      if guid.blank?
        Rails.logger.error "[Data API] Guid is missing: guid=`#{guid}`"
        return nil
      end

      url = "#{Rails.application.config.data_api_url}/institutions/#{guid}/artifacts/report/#{date}"
      locale = locale.to_s.downcase.start_with?('en') ? 'en' : 'pt'

      formats = ['csv', 'xls']
      report_download_links = {}

      threads = formats.map do |format|
        Thread.new do
          query = {
            language: locale,
            format: format
          }

          conn = Faraday.new(url: url) do |config|
            config.response :json
          end

          response = conn.get(url, query)

          if response.status == 400
            Rails.logger.info "[Data API] Bad request (guid: #{guid} and date: #{date})"
          end

          report_download_links[format] = response.body['link']
        end
      end

      # Wait for all threads to finish
      threads.each(&:join)
      report_download_links
    end

    # Calls the method `list_objects` to get the link for artifacts of meeting
    # Returns a hash with the links from the response
    #
    # @return [Hash] with 3 keys: participants_list, shared_notes, engagement_report
    def self.get_meeting_artifacts_files(guid, internal_meeting_id)
      check_api_url

      return nil if guid.blank?

      key_mapping = {
        "activities.txt" => "participants_list",
        "notes.txt" => "shared_notes",
        "learning_dashboard.json" => "engagement_report"
      }

      artifact_download_links = {}

      meeting_objects = list_objects(guid, internal_meeting_id)

      if meeting_objects.present?
        artifact_download_links = meeting_objects.each_with_object({}) do |artifact, result|
          if key_mapping.key?(artifact["file_name"])
            artifact_file = key_mapping[artifact["file_name"]]
            result[artifact_file] = artifact["link"]
          end
        end
      end

      artifact_download_links
    end

    # Calls the API to get the objects of a meeting
    # Returns a hash with the links from the API's response
    #
    # @return [Hash] with all artifacts related to that meeting
    def self.list_objects(guid, internal_meeting_id)
      check_api_url

      return nil if guid.blank?

      url = "#{Rails.application.config.data_api_url}/institutions/#{guid}/artifacts/meetings/#{internal_meeting_id}/list_objects"

      conn = Faraday.new(url: url) do |config|
        config.response :json
      end

      response = conn.get(url)

      if response.status == 400
        Rails.logger.error "[Data API] Bad request (guid: #{guid} and internal_meeting_id: #{internal_meeting_id})"
      elsif response.status == 404
        Rails.logger.error "[Data API] Meeting or file not found (guid: #{guid} and internal_meeting_id: #{internal_meeting_id})"
      end

      response.body["objects"]
    end

    private

    # Raises ApiUrlMissingError if the API URL is missing from the application config
    private_class_method def self.check_api_url
      if Rails.application.config.data_api_url.blank?
        raise ApiUrlMissingError, 'Data API URL config is missing.'
      end
    end
  end
end
