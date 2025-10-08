require 'bigbluebutton_api'
require 'bbb_api'
require './lib/mconf/eduplay'

class UploadRecordingToEduplayJob < ApplicationJob
  include BbbApi
  queue_as :default

  def perform(room, rec_id, video_data, user)
    begin
      @recording = get_recordings(room, recordID: rec_id).first.first
      video_data = video_data.symbolize_keys
      @eduplay_token = EduplayToken.find_by(user_uid: user[:uid])
      playback = @recording[:playbacks].find { |f| f[:type] == 'video' } || @recording[:playbacks].find { |f| f[:type] == 'presentation_video' }

      if playback.nil?
        return Resque.logger.error "[UploadRecordingToEduplayJob] Recording #{rec_id} has no video playback format"
      end

      Resque.logger.info "[UploadRecordingToEduplayJob] Starting upload to Eduplay Worker, recording #{rec_id}"

      # If the recordings server uses token authentication, we must get an authenticated
      # download URL
      rec_url = URI.parse(playback[:url])
      if Rails.application.config.playback_url_authentication
        token = get_recording_token(room, user[:full_name], rec_id)
        rec_url.query = URI.encode_www_form({ token: token })
      end

      api = Mconf::Eduplay::API.new(@eduplay_token.token)

      Resque.logger.info "[UploadRecordingToEduplayJob] Creating tags #{video_data[:tags]} ..."
      api.create_multiple_tags(video_data[:tags])

      Resque.logger.info "[UploadRecordingToEduplayJob] Downloading #{rec_url} ..."
      file = api.download_file rec_url

      if file.nil?
        return Resque.logger.error "[UploadRecordingToEduplayJob] File is not a video"
      end

      Resque.logger.info "[UploadRecordingToEduplayJob] Recording downloaded. Size: #{file.size} bytes, extension: #{File.extname(file)}. Recording (#{rec_id})"

      Resque.logger.info "[UploadRecordingToEduplayJob] Getting upload link file..."
      data = api.get_upload_link(video_data[:title], File.extname(file))

      Resque.logger.info "[UploadRecordingToEduplayJob] Uploading file..."
      up_file_res = api.upload_file(data['url'], file.path)

      Resque.logger.info "[UploadRecordingToEduplayJob] Creating video #{@eduplay_token.user_uid}, #{data['identifier']}, #{data['filename']}..."

      # Handle thumbnail from database if present
      tempfile = nil
      eduplay_upload_id = video_data[:eduplay_upload_id]
      if eduplay_upload_id.is_a?(Integer)
        eduplay_upload = EduplayUpload.find_by(id: eduplay_upload_id)

        if eduplay_upload&.thumbnail_data&.present?
          begin
            Resque.logger.info "[UploadRecordingToEduplayJob] Loading thumbnail from database (EduplayUpload ID: #{eduplay_upload_id})"

            extension = case eduplay_upload.thumbnail_content_type
                       when 'image/jpeg', 'image/jpg' then '.jpg'
                       when 'image/png' then '.png'
                       when 'image/gif' then '.gif'
                       else '.jpg'
                       end

            unique_name = "eduplay_thumbnail_#{SecureRandom.hex(8)}"
            tempfile = Tempfile.new([unique_name, extension], binmode: true)
            tempfile.write(eduplay_upload.thumbnail_data)
            tempfile.close

            video_data = video_data.merge(thumbnail: [tempfile.path, eduplay_upload.thumbnail_content_type])

            Resque.logger.info "[UploadRecordingToEduplayJob] Thumbnail loaded from database successfully (temp file: #{File.basename(tempfile.path)})"
          rescue => e
            Resque.logger.error "[UploadRecordingToEduplayJob] Failed to load thumbnail from database: #{e.message}"
            video_data = video_data.merge(thumbnail: nil)
          end
        elsif eduplay_upload
          Resque.logger.info "[UploadRecordingToEduplayJob] No thumbnail data found for EduplayUpload ID: #{eduplay_upload_id}"
          video_data = video_data.merge(thumbnail: nil)
        else
          Resque.logger.error "[UploadRecordingToEduplayJob] EduplayUpload not found with ID: #{eduplay_upload_id}"
          video_data = video_data.merge(thumbnail: nil)
        end
      end
      
      video = api.create_video(data, video_data)

      if video['success']
        Resque.logger.info "[UploadRecordingToEduplayJob] Upload video recording to Eduplay rec_id: #{rec_id} video: #{video.inspect}"
      else
        Resque.logger.error "[UploadRecordingToEduplayJob] Error uploading video to Eduplay: #{video.inspect}"
      end
    ensure
      # Clean up temporary files
      if tempfile && File.exist?(tempfile.path)
        tempfile.close unless tempfile.closed?
        tempfile.unlink
      end

      if defined?(file) && file.respond_to?(:unlink)
        file.close unless file.closed?
        file.unlink
      end

      # Clean up thumbnail data from database
      if eduplay_upload_id.is_a?(Integer)
        eduplay_upload = EduplayUpload.find_by(id: eduplay_upload_id)
        if eduplay_upload&.thumbnail_data&.present?
          begin
            eduplay_upload.update!(thumbnail_data: nil, thumbnail_content_type: nil)
            Resque.logger.info "[UploadRecordingToEduplayJob] Cleaned up thumbnail data from database (EduplayUpload ID: #{eduplay_upload_id})"
          rescue => e
            Resque.logger.error "[UploadRecordingToEduplayJob] Failed to cleanup thumbnail data from database: #{e.message}"
          end
        end
      end
    end
  end
end
