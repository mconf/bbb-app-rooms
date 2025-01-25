module Mconf
  class DataApi
    class ApiUrlMissingError < StandardError; end

    # Calls the API to get the link for artifacts of given month
    # Returns a hash with the links from the API's response
    #
    # @return [Hash] with 3 keys: pdf, csv and xls
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

    # Calls the API to get the link for artifacts of of a recording
    # Returns a hash with the links from the API's response
    #
    # @return [Hash] with 3 keys: participants_list, shared_notes, engagement_report
    def self.get_meeting_artifacts_files(guid, internal_meeting_id)
      check_api_url

      return nil if guid.blank?

      Rails.logger.info "[Data API] Get meeting artifact files"

      files = ['participants_list', 'shared_notes', 'engagement_report']
      artifact_download_links = {}

      threads = files.map do |file|
        Thread.new do
          url = "#{Rails.application.config.data_api_url}/institutions/#{guid}/artifacts/meetings/#{internal_meeting_id}/#{file}"

          conn = Faraday.new(url: url) do |config|
            config.response :json
          end

          response = conn.get(url)

          if response.status == 400
            Rails.logger.error "[Data API] Bad request (guid: #{guid} and date: #{date})"
          end

          artifact_download_links[file] = response.body['link']
        end
      end

      # Wait for all threads to finish
      threads.each(&:join)
      artifact_download_links
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
