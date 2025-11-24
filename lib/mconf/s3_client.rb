# module to interact with AWS S3 API
# uses 'aws-sdk-s3' gem
module Mconf::S3Client

  BUCKET_NAME = Mconf::Env.fetch('AWS_PUBLIC_BUCKET_NAME', nil)
  STORE_PATH = 'uploads/profile_image'.freeze

  # Returns an Aws::S3::Client instance
  # @return [Aws::S3::Client]
  def self.client
    attrs = {
      access_key_id: Mconf::Env.fetch('AWS_PUBLIC_BUCKET_ACCESS_KEY_ID'),
      secret_access_key: Mconf::Env.fetch('AWS_PUBLIC_BUCKET_SECRET_ACCESS_KEY'),
      region: Mconf::Env.fetch('AWS_PUBLIC_BUCKET_REGION'),
      force_path_style: true
    }

    Aws::S3::Client.new(attrs)
  rescue StandardError => e
    Rails.logger.error "Error on AWS S3 Client configuration: #{e.message}"
    nil
  end

  # Returns the public URL for a file stored in S3
  # e.g. https://bucket-hmg-public.s3.amazonaws.com/uploads/profile_image/8aec81df-1948-4f78-ad24-70daa21cdbeb_409.jpg
  # @param file_name [String] the name of the file
  # @return [String] the public URL of the file
  def self.url_for(file_name)
    "https://#{BUCKET_NAME}.s3.amazonaws.com/#{STORE_PATH}/#{file_name}"
  end

  # List files in the S3 bucket with the given prefix
  # @param prefix [String] the prefix to filter objects
  # @return [nil]
  def self.list_files(prefix: '')
    client.list_objects_v2(
      bucket: BUCKET_NAME,
      prefix: prefix
    ).each do |ret|
      ret.contents.each do |r|
        Rails.logger.info r.inspect
      end
    end
  rescue StandardError => e
    Rails.logger.error "[S3Client] Error: #{e.message}"
    nil
  end

  # Uploads a file to the S3 bucket
  # @param file_body [IO, String] the file body to upload
  # @param file_name [String] the name of the file to upload
  # @return [String, nil] the S3 object key if upload is successful, nil otherwise
  def self.upload_public_file(file_body, file_name)
    object_key = "#{STORE_PATH}/#{file_name}"

    res = client.put_object(
      acl: 'public-read',
      bucket: BUCKET_NAME,
      key: object_key,
      body: file_body
    )
    if res.etag.blank?
      Rails.logger.warn "[S3Client] File '#{object_key}' could not be uploaded to bucket '#{BUCKET_NAME}'"
      return nil
    end

    Rails.logger.info "[S3Client] File '#{object_key}' uploaded to bucket '#{BUCKET_NAME}'"
    object_key
  rescue StandardError => e
    Rails.logger.error "[S3Client] Error: #{e.message}"
    nil
  end

  # Deletes a file from the S3 bucket
  # @param file_name [String] the name of the file to delete
  # @return [Boolean] true if deletion is successful, false otherwise
  def self.delete_file(file_name)
    object_key = "#{STORE_PATH}/#{file_name}"

    ret = client.delete_object(bucket: BUCKET_NAME, key: object_key)
    if ret.delete_marker.blank?
      Rails.logger.warn "[S3Client] File '#{object_key}' could not be deleted from bucket '#{BUCKET_NAME}'"
      return false
    end

    Rails.logger.info "[S3Client] File '#{object_key}' deleted from bucket '#{BUCKET_NAME}'"
    true
  rescue StandardError => e
    Rails.logger.error "[S3Client] Error: #{e.message}"
    false
  end
end
