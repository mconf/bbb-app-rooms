module Mconf
  class DataApi
    class ApiUrlMissingError < StandardError; end

    # Documents generated for the session, without depending on a recording, are stored
    # under this prefix. The ones at the root of the meeting are made from the recording.
    SESSION_DOCUMENTS_PREFIX = 'no_record/'.freeze

    # Documents made by the LLM, available for the session and for the recording
    AI_DOCUMENT_FILE_NAMES = {
      'summary.txt' => 'ai_summary',
      'transcription.txt' => 'transcription'
    }.freeze

    # Documents of the meeting itself, which exist regardless of a recording
    MEETING_DOCUMENT_FILE_NAMES = {
      'activities.txt' => 'participants_list',
      'notes.txt' => 'shared_notes'
    }.freeze

    # Calls the API to get the link for artifacts of given month
    # Returns a hash with the links from the API's response
    #
    # @return [Hash] with 2 keys: csv and xls
    def self.get_report_artifacts(consumer_key, handler, date, locale = 'pt')
      check_api_url

      if consumer_key.blank? || handler.blank?
        Rails.logger.error "[Data API] Consumer key or Room handler is missing: consumer_key=`#{consumer_key}`, handler=`#{handler}`"
        return nil
      end

      url = "#{Rails.application.config.data_api_url}/lti/#{consumer_key}/#{handler}/artifacts/report/#{date}"
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
            Rails.logger.error "[Data API] Bad request (consumer_key: #{consumer_key} and handler: #{handler})"
          elsif response.status == 404
            Rails.logger.error "[Data API] File not found"
          end

          report_download_links[format] = response.body['link']
        end
      end

      # Wait for all threads to finish
      threads.each(&:join)
      report_download_links
    end

    def self.reports_available(consumer_key, handler)
      check_api_url

      if consumer_key.blank? || handler.blank?
        Rails.logger.error "[Data API] Consumer key or Room handler is missing: consumer_key=`#{consumer_key}`, handler=`#{handler}`"
        return nil
      end

      url = "#{Rails.application.config.data_api_url}/lti/#{consumer_key}/#{handler}/artifacts/reports_available"

      conn = Faraday.new(url: url) do |config|
        config.response :json
      end

      response = conn.get(url)

      if response.status == 400
        Rails.logger.error "[Data API] Bad request (consumer_key: #{consumer_key} and handler: #{handler})"
        return nil
      elsif response.status == 404
        Rails.logger.error "[Data API] No reports found"
        return nil
      end

      response.body
    end

    # Calls the API to get the download links for every document of a meeting, grouped by
    # what they were made from: the meeting itself, the session or the recording.
    #
    # The AI documents of the session are made from what was transcribed live, so they
    # exist even when the meeting was not recorded. The ones of the recording are made
    # from it after it is processed.
    #
    # @return [Hash] with 3 keys, each one a hash of document type to link:
    #   'meeting'   => participants_list, shared_notes, engagement_report
    #   'session'   => ai_summary, transcription
    #   'recording' => ai_summary, transcription
    def self.get_meeting_documents(guid, internal_meeting_id, locale = 'pt-BR')
      check_api_url

      return nil if guid.blank?

      documents = { 'meeting' => {}, 'session' => {}, 'recording' => {} }

      list_objects(guid, internal_meeting_id)&.each do |object|
        group, document_type = classify_document(object['file_name'])
        next if document_type.blank?

        documents[group][document_type] = object['link']
      end

      # engagement_report is not listed with the objects, it has an endpoint of its own
      engagement_report = get_engagement_report(guid, internal_meeting_id, locale)
      documents['meeting']['engagement_report'] = engagement_report if engagement_report.present?

      documents
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
        Rails.logger.error "[Data API] Meeting or files not found (guid: #{guid} and internal_meeting_id: #{internal_meeting_id})"
      end

      response.body["objects"]
    end

    # Calls the API to get the engagement report of a meeting
    # Returns the link from the API's response
    #
    # @return Meeting's engagement report link
    def self.get_engagement_report(guid, internal_meeting_id, locale = 'pt-BR')
      check_api_url

      return nil if guid.blank?

      url = "#{Rails.application.config.data_api_url}/institutions/#{guid}/artifacts/meetings/#{internal_meeting_id}/engagement_report?ld_redirect=true"

      conn = Faraday.new(url: url) do |config|
        config.response :json
      end

      response = conn.get(url)

      if response.status == 400
        Rails.logger.error "[Data API] Bad request (guid: #{guid} and internal_meeting_id: #{internal_meeting_id})"
      elsif response.status == 404
        Rails.logger.error "[Data API] Meeting or file not found (guid: #{guid} and internal_meeting_id: #{internal_meeting_id})"
      end

      locale = 'pt-BR' if locale.eql?('pt')

      return nil if response.body["error"].present?

      response_link = response.body['link']
      response_link = "#{response_link}&lang=#{locale}" if response_link.present?

      response_link
    end

    private

    # Tells which group a document listed for the meeting belongs to, from its file name
    #
    # @return [Array] the group ('meeting', 'session' or 'recording') and the document
    #   type, or nils when the file is not one of the documents shown to the user
    private_class_method def self.classify_document(file_name)
      return [nil, nil] if file_name.blank?

      if file_name.start_with?(SESSION_DOCUMENTS_PREFIX)
        ['session', AI_DOCUMENT_FILE_NAMES[file_name.delete_prefix(SESSION_DOCUMENTS_PREFIX)]]
      elsif AI_DOCUMENT_FILE_NAMES.key?(file_name)
        ['recording', AI_DOCUMENT_FILE_NAMES[file_name]]
      else
        ['meeting', MEETING_DOCUMENT_FILE_NAMES[file_name]]
      end
    end

    # Raises ApiUrlMissingError if the API URL is missing from the application config
    private_class_method def self.check_api_url
      if Rails.application.config.data_api_url.blank?
        raise ApiUrlMissingError, 'Data API URL config is missing.'
      end
    end
  end
end
