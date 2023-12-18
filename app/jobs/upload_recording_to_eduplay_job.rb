require 'bigbluebutton_api'
require 'bbb_api'
require './lib/mconf/eduplay'

class UploadRecordingToEduplayJob < ApplicationJob
  include BbbApi
  queue_as :default

  def perform(room, rec_id, user)
    @recording = get_recordings(room, recordID: rec_id).first.first
    @eduplay_token = EduplayToken.find_by(user_uid: user[:uid])
    playback = @recording[:playbacks].find{ |f| f[:type] == 'presentation_video' }

    if playback.nil?
      return Resque.logger.error "Recording #{rec_id} has no video playback format"
    end

    Resque.logger.info "Starting upload to Eduplay Worker, recording (#{@recording[:recordID]})"

    client_host = Rails.application.config.eduplay_service_url
    client_secret = Rails.application.config.eduplay_client_secret

    # If the recordings server uses token authentication, we must get an authenticated
    # download URL
    rec_url = URI.parse(playback[:url])
    if Rails.application.config.playback_url_authentication
      token = get_recording_token(room, user[:full_name], params[:record_id])
      rec_url.query = URI.encode_www_form({ token: token })
    end

    api = Eduplay::API.new(client_host, @eduplay_token.token, client_secret)

    Resque.logger.info "[+] Downloading #{rec_url} ..."
    file = api.download_file rec_url

    if file.nil?
      return Resque.logger.error "File is not a video"
    end

    Resque.logger.info "[+] Recording downloaded. Size: #{file.size} bytes, extension: #{File.extname(file)}. Recording (#{@recording[:recordID]})"

    Resque.logger.info "[+] Getting upload link file..."
    data = api.get_upload_link(nil, nil, File.extname(file))

    Resque.logger.info "[+] Uploading file..."
    api.upload_file data['result'], file.path

    Resque.logger.info "[+] Creating video #{@eduplay_token.user_uid}, #{data['id']}, #{data['filename']}..."

    video = api.create_video @eduplay_token.user_uid, data['id'], data['filename'], title: @recording[:name]

    Resque.logger.info "[+] Upload video recording to Eduplay rec_id: #{rec_id} video: #{video.inspect}"
  end
end
