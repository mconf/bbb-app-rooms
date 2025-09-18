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
        return Resque.logger.error "Recording #{rec_id} has no video playback format"
      end

      Resque.logger.info "Starting upload to Eduplay Worker, recording #{rec_id}"

      # If the recordings server uses token authentication, we must get an authenticated
      # download URL
      rec_url = URI.parse(playback[:url])
      if Rails.application.config.playback_url_authentication
        token = get_recording_token(room, user[:full_name], rec_id)
        rec_url.query = URI.encode_www_form({ token: token })
      end

      api = Mconf::Eduplay::API.new(@eduplay_token.token)

      Resque.logger.info "[+] Creating tags #{video_data[:tags]} ..."
      api.create_multiple_tags(video_data[:tags])

      Resque.logger.info "[+] Downloading #{rec_url} ..."
      file = api.download_file rec_url

      if file.nil?
        return Resque.logger.error "File is not a video"
      end

      Resque.logger.info "[+] Recording downloaded. Size: #{file.size} bytes, extension: #{File.extname(file)}. Recording (#{rec_id})"

      Resque.logger.info "[+] Getting upload link file..."
      data = api.get_upload_link(video_data[:title], File.extname(file))

      Resque.logger.info "[+] Uploading file..."
      up_file_res = api.upload_file(data['url'], file.path)

      Resque.logger.info "[+] Creating video #{@eduplay_token.user_uid}, #{data['identifier']}, #{data['filename']}..."
      video = api.create_video(data, video_data)

      if video['success']
        Resque.logger.info "[+] Upload video recording to Eduplay rec_id: #{rec_id} video: #{video.inspect}"
      else
        Resque.logger.error "[+] Error uploading video to Eduplay: #{video.inspect}"
      end
    ensure
      if video_data[:thumbnail].present?
        File.delete(video_data[:thumbnail][0]) if File.exist?(video_data[:thumbnail][0])
      end
    end
  end
end
