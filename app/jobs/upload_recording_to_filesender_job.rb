require 'bigbluebutton_api'
require 'bbb_api'
require './lib/mconf/filesender'

class UploadRecordingToFilesenderJob < ApplicationJob
  include BbbApi
  queue_as :default

  # Uploads a recording to Filesender
  def perform(room, rec_id, user, data)
    @recording = get_recordings(room, recordID: rec_id).first.first
    # @user = User.find(user_id)
    @filesender_token = FilesenderToken.find_by(user_uid: user[:uid])
    @playback = @recording[:playbacks].find{ |f| f[:type] == 'presentation_video' }

    if @playback.nil?
      return Resque.logger.error "Recording #{rec_id} has no video playback format"
    end

    Resque.logger.info "Starting upload to Filesender Worker, recording (#{@recording[:recordID]})"

    client_host = Rails.application.config.filesender_service_url + '/rest.php'
    client_secret = Rails.application.config.filesender_client_secret
    mode = 'oauth' # always oauth (for now)
    appid = Rails.application.config.filesender_client_id # mconf id

    # If the recordings server uses token authentication, we must get an authenticated
    rec_url = URI.parse(@playback[:url])
    if Rails.application.config.playback_url_authentication
      token = get_recording_token(room, user[:full_name], rec_id)
      rec_url.query = URI.encode_www_form({ token: token })
    end

    api = Filesender::API.new(client_host, mode, @filesender_token.token, client_secret)
    # Resque.logger.info "[+] api: #{api.inspect}..."

    # Download the video then upload it to Filesender
    Resque.logger.info "[+] Downloading #{rec_url} ..."
    file = api.download_file rec_url

    if file.nil?
      return Resque.logger.error "File is not a video"
    end

    Resque.logger.info "[+] Recording downloaded. Size: #{file.size} bytes, extension: #{File.extname(file)}. Recording (#{@recording[:recordID]})"

    Resque.logger.info "[+] Getting rec_url..."
    fpath = file.path

    Resque.logger.info "[+] Creating video #{@filesender_token.token}..."
    api.send_file(@filesender_token.token, fpath, data, user)

    Resque.logger.info "[+] Worker finished"
  end
end
