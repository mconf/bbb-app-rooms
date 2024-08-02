module Mconf
  class BucketApi

    class BucketConfigMissingError < StandardError; end

    REQUIRED_CONFIGS = %i[meetings_bucket_key_id meetings_bucket_secret meetings_bucket_region meetings_bucket_name]

    def self.client
      check_bucket_configs

      attrs = {
        access_key_id: Rails.application.config.meetings_bucket_key_id,
        secret_access_key: Rails.application.config.meetings_bucket_secret,
        region: Rails.application.config.meetings_bucket_region,
        force_path_style: true
      }
      # to leave it empty in case an endpoint is not configured
      # doesn't work setting the endpoint to nil, really need to not set the attribute
      unless Rails.application.config.meetings_bucket_endpoint.blank?
        attrs[:endpoint] = Rails.application.config.meetings_bucket_endpoint
      end
      client = Aws::S3::Client.new(attrs)

      client
    end

    def self.gen_key(meeting, file_name)
      uuid = ApplicationHelper.get_shared_secret_guid(meeting[:room]) || ""
      external_meeting_id = meeting[:meetingID] || ""
      internal_meeting_id = meeting[:internalMeetingID] || ""
      key = uuid + "/" + external_meeting_id + "/" + internal_meeting_id + "/" + file_name

      key
    end
    
    def self.gen_min_key(meeting)
      uuid = ApplicationHelper.get_shared_secret_guid(meeting[:room]) || ""
      external_meeting_id = meeting[:meetingID] || ""
      key = uuid + "/" + external_meeting_id

      key
    end

    def self.download_url(meeting, file_name)
      check_bucket_configs

      key = gen_key(meeting, file_name)
      signer = Aws::S3::Presigner.new(client: client)

      url = signer.presigned_url(
        :get_object,
        bucket: Rails.application.config.meetings_bucket_name,
        key: key,
        expires_in: Rails.application.config.meetings_bucket_expires_in,
        response_content_disposition: 'attachment' # force a download
      )

      url
    end

    def self.file_exists?(meeting, path)
      check_bucket_configs

      begin
        ret = client.list_objects_v2(
          bucket: Rails.application.config.meetings_bucket_name,
          prefix: gen_min_key(meeting)
        )

        ret.contents.find { |i| i[:key] == path }.present?
      rescue Aws::S3::Errors::NotFound
        false
      end

    end

    def self.list_objects(prefix = '')
      ret = client.list_objects_v2(
        bucket: Rails.application.config.meetings_bucket_name,
        prefix: prefix
      )
      ret.contents.each do |r|
        puts r
      end
    end

    def self.delete_object(key)
      client.delete_object({
        bucket: Rails.application.config.meetings_bucket_name,
        key: key
      })
    end

    def self.upload_file_object()
      bucket_name = Rails.application.config.meetings_bucket_name

      # /shared_secret_guid/external_meeting_id/internal_meeting_id/file.txt
      object_key = 'key'

      File.open('notes.txt', 'rb') do |file|
        res = client.put_object(bucket: bucket_name, key: object_key, body: file)
        if res.etag
          puts "Object '#{object_key}' uploaded to bucket '#{bucket_name}'."
          true
        else
          puts "Object '#{object_key}' not uploaded to bucket '#{bucket_name}'."
          false
        end
      end
    end

    private

    # Raises BucketConfigMissingError if any required config is missing
    private_class_method def self.check_bucket_configs
      REQUIRED_CONFIGS.each do |config|
        if Rails.application.config.send(config).blank?
          raise BucketConfigMissingError, "Bucket required config missing: #{config.to_s}"
        end
      end
    end

  end
end
