# frozen_string_literal: true

require 'net/http'
require 'user'
require 'bbb_api'
require './lib/mconf/eduplay'
require './lib/mconf/filesender'

class RoomsController < ApplicationController
  include ApplicationHelper
  include BbbApi
  include BbbAppRooms

  before_action -> {authenticate_with_oauth! :bbbltibroker},
    only: :launch, raise: false
  before_action :set_launch_room, only: %i[launch]

  before_action :find_room, except: %i[launch close]
  before_action :validate_room, except: %i[launch close]
  before_action :find_user
  before_action :find_app_launch, only: %i[launch]
  before_action :set_room_title, only: :show

  before_action only: %i[show launch close] do
    authorize_user!(:show, @room)
  end
  before_action only: %i[edit update recording_publish recording_unpublish
                         recording_update recording_delete] do
    authorize_user!(:edit, @room)
  end

  # GET /rooms/1
  def show
    respond_to do |format|
      # TODO: do this also in a worker in the future to speed up this request
      @room.update_recurring_meetings

      @scheduled_meetings = @room.scheduled_meetings.active
                              .order(:start_at).page(params[:page])

      format.html { render :show }
    end
  end

  def meetings
    @fetch_meetings_endpoint = meetings_pagination_room_path
    @per_page = Rails.application.config.meetings_per_page
  end

  def meetings_pagination
    offset = params[:offset].to_i
    limit = (params[:limit] || 1).to_i

    options = {
      limit: limit,
      offset: offset,
      includeRecordings: true
    }
    meetings_and_recordings, all_meetings_loaded = get_all_meetings(@room, options)

    args = { meetings_and_recordings: meetings_and_recordings,
             user: @user,
             room: @room,
             all_meetings_loaded: all_meetings_loaded }

    render partial: 'shared/meetings_list',
           layout: false,
           locals: args
  end

  # GET /launch
  def launch
    scheduled_meeting_id = @app_launch.custom_param('scheduled_meeting')
    scheduled_meeting = ScheduledMeeting.find_by_id(scheduled_meeting_id)
    if scheduled_meeting
      redirect_to(external_room_scheduled_meeting_path(@room, scheduled_meeting))
    else
      redirect_to(room_path(@room))
    end
  end

  # GET /rooms/close
  # A simple page that closes itself
  def close
    respond_to do |format|
      format.html { render :autoclose }
    end
  end

  # GET /rooms/:id/recording/:record_id/playback/:playback_type
  def recording_playback
    # get_recordings returns [[{rec_hash}], boolean]
    recording = get_recordings(@room, recordID: params[:record_id]).first.first
    playback = recording[:playbacks].find { |p| p[:type] == params[:playback_type] }
    playback_url = URI.parse(playback[:url])
    if Rails.application.config.playback_url_authentication
      token = get_recording_token(@room, @user.full_name, params[:record_id])
      playback_url.query = URI.encode_www_form({ token: token })
    end
    redirect_to(playback_url.to_s)
  end

  # POST /rooms/:id/recording/:record_id/unpublish
  def recording_unpublish
    unpublish_recording(@room, params[:record_id])
    redirect_to(meetings_room_path(@room, filter: params[:filter]))
  end

  # POST /rooms/:id/recording/:record_id/publish
  def recording_publish
    publish_recording(@room, params[:record_id])
    redirect_to(meetings_room_path(@room, filter: params[:filter]))
  end

  # POST /rooms/:id/recording/:record_id/update
  def recording_update
    if params[:setting] == "rename_recording"
      update_recording(@room, params[:record_id], "meta_name" => params[:record_name])
    elsif params[:setting] == "describe_recording"
      update_recording(@room, params[:record_id], "meta_description" => params[:record_description])
    end
    redirect_to(meetings_room_path(@room, filter: params[:filter]))
  end

  # POST /rooms/:id/recording/:record_id/delete
  def recording_delete
    delete_recording(@room, params[:record_id])
    redirect_to(meetings_room_path(@room, filter: params[:filter]))
  end

  def error
    error_code = params[:code]
    path = room_path(@room)
    redirect_args = [path]

    case error_code
    when 'oauth_error'
      notice = t('default.rooms.error.oauth')
      redirect_args << { notice: notice }
    end
    redirect_to(*redirect_args)
  end

  def eduplay_upload
    old_eduplay_token = EduplayToken.find_by(user_uid: @user.uid)
    if params['access_token'].present?
      if old_eduplay_token.nil?
        EduplayToken.create!(user_uid: @user.uid, token: params['access_token'], expires_at: params['expires_at'])
      else
        old_eduplay_token.update(token: params['access_token'], expires_at: params['expires_at'])
      end
    else
      if old_eduplay_token.nil?
        flash[:notice] = t('default.eduplay.error')
        redirect_to(meetings_room_path(@room, filter: params[:filter])) and return
      end
    end

    flash[:notice] = t('default.eduplay.success')
    UploadRecordingToEduplayJob.perform_later(@room, params['record_id'], @user.as_json.symbolize_keys)
    redirect_to(meetings_room_path(@room, filter: params[:filter]))
  end

  # GET	/rooms/:id/recording/:record_id/filesender
  def filesender
    filesender_token = FilesenderToken.find_by(user_uid: @user.uid)
    if filesender_token.nil? || filesender_token.expires_at < Time.now + 5
      flash[:notice] = t('default.eduplay.error')
      redirect_to(meetings_room_path(@room)) and return
    end

    recording = get_recordings(@room, recordID: params[:record_id]).first

    render "rooms/filesender"
  end

  # POST /rooms/:id/recording/:record_id/filesender_upload
  def filesender_upload
    data = {
      subject: params['subject'],
      message: params['message'],
      recipients: params['emails'].split(',').uniq
    }

    flash[:notice] = t('default.filesender.success')
    UploadRecordingToFilesenderJob.perform_later(@room, params['record_id'], @user.as_json.symbolize_keys, data)
    redirect_to(meetings_room_path(@room))
  end

  # POST /rooms/:id/recording/:record_id/filesender
  def filesender_auth
    old_filesender_token = FilesenderToken.find_by(user_uid: @user.uid)
    if params['access_token'].present?
      if old_filesender_token.nil?
        FilesenderToken.create!(user_uid: @user.uid, token: params['access_token'], expires_at: params['expires_at'])
      else
        old_filesender_token.update(token: params['access_token'], expires_at: params['expires_at'])
      end
    else
      if old_filesender_token.nil?
        flash[:notice] = t('default.filesender.error')
        redirect_to(meetings_room_path(@room, filter: params[:filter])) and return
      end
    end

    redirect_to(filesender_path(@room, record_id: params['record_id']))
  end

  helper_method :meetings, :recording_date, :recording_length

  private

  def set_launch_room
    launch_nonce = params['launch_nonce']

    # Pull the Launch request_parameters
    bbbltibroker_url = omniauth_bbbltibroker_url("/api/v1/sessions/#{launch_nonce}")
    Rails.logger.info "Making a session request to #{bbbltibroker_url}"
    session_params = JSON.parse(
      RestClient.get(
        bbbltibroker_url,
        'Authorization' => "Bearer #{omniauth_client_token(omniauth_bbbltibroker_url)}"
      )
    )

    unless session_params['valid']
      Rails.logger.info "The session is not valid, returning a 403"
      set_error('room', 'forbidden', :forbidden)
      respond_with_error(@error)
      return
    end

    launch_params = session_params['message']
    if launch_params['user_id'] != session['omniauth_auth']['bbbltibroker']['uid']
      Rails.logger.info "The user in the session doesn't match the user in the launch, returning a 403"
      set_error('room', 'forbidden', :forbidden)
      respond_with_error(@error)
      return
    end

    # it's null unless we get an external handler below
    handler = nil

    # will only try to get an external context/handler if the ConsumerConfig is configured to do so
    if launch_params.key?('custom_params') && launch_params['custom_params'].key?('oauth_consumer_key')
      consumer_key = launch_params['custom_params']['oauth_consumer_key']
      if consumer_key.present?
        ext_context_url = ConsumerConfig.find_by(key: consumer_key)&.external_context_url
      end
    end
    if ext_context_url.present?
      Rails.logger.info "The consumer is configured to use an API to fetch the context/handler consumer_key=#{consumer_key} url=#{ext_context_url}"

      # if the handler was already set, try to use it
      # this will happen in the 2nd step, after the user selects a handler/room to access
      handler = params['handler']
      Rails.logger.info "Found a handler in the params, will try to use it handler=#{handler}" unless handler.nil?
      # TODO: maybe use an extra param or the session to validate the request

      if handler.blank?
        Rails.logger.info "Making a request to an external API to define the context/handler url=#{ext_context_url}"
        begin
          response = send_request(ext_context_url, launch_params)
          # example response:
          # [
          #   {
          #     "class_name": "STRW18/Q08.01",
          #     "handler": "61128015393ef38d7a2af97e0b80184432428c6b"
          #   }
          # ]
          handlers = JSON.parse(response.body)
        rescue JSON::ParserError => error
          # TODO: log and render error
          raise error
        rescue StandardException => error
          # TODO: log and render error
          raise error
        end

        if handlers.size == 0
          Rails.logger.warn "Couldn't define a handler using the external request"
          # TODO: render error page
        elsif handlers.size > 1
          @handlers = handlers
          @launch_nonce = launch_nonce
          user_params = AppLaunch.new(params: launch_params).user_params
          @user = BbbAppRooms::User.new(user_params)
          set_current_locale
          respond_to do |format|
            format.html { render 'rooms/external_context_selector' }
          end
          return
        else
          handler = handlers.first['handler']
          Rails.logger.info "Defined a handler using the external request handler=#{handler}"
        end
      end
    end

    bbbltibroker_url = omniauth_bbbltibroker_url("/api/v1/sessions/#{launch_nonce}/invalidate")
    Rails.logger.info "Making a session request to #{bbbltibroker_url}"
    session_params = JSON.parse(
      RestClient.get(
        bbbltibroker_url,
        'Authorization' => "Bearer #{omniauth_client_token(omniauth_bbbltibroker_url)}"
      )
    )

    # Store the data from this launch for easier access
    expires_at = Rails.configuration.launch_duration_mins.from_now
    app_launch = AppLaunch.create_with(room_handler: handler)
                   .find_or_create_by(nonce: launch_nonce) do |launch|
      launch.update(
        params: launch_params,
        omniauth_auth: session['omniauth_auth']['bbbltibroker'],
        expires_at: expires_at
      )
    end
    Rails.logger.info "Saved the AppLaunch nonce=#{app_launch.nonce} room_handler=#{app_launch.room_handler}"

    # Use this data only during the launch
    # From now on, take it from the AppLaunch
    session.delete('omniauth_auth')

    # Create/update the room
    local_room_params = app_launch.room_params
    @room = Room.create_with(local_room_params)
              .find_or_create_by(handler: local_room_params[:handler])
    @room.update(local_room_params) if @room.present?

    # Create the user session
    # Keep it as small as possible, most of the data is in the AppLaunch
    set_room_session(
      @room, { launch: launch_nonce }
    )
  end

  def set_room_title
    if @app_launch&.coc_launch?
      @title = @room.name
      @subtitle = @room.description
    end
  end

  def send_request(url, data=nil)
    url_parsed = URI.parse(url)
    http = Net::HTTP.new(url_parsed.host, url_parsed.port)
    http.open_timeout = 30
    http.read_timeout = 30
    http.use_ssl = true if url_parsed.scheme.downcase == 'https'

    if data.nil?
      Rails.logger.info "Sending a GET request to '#{url}'"
      response = http.get(url_parsed.request_uri, @request_headers)
    else
      data = data.to_json
      Rails.logger.info "Sending a POST request to '#{url}' with data='#{data.inspect}' (size=#{data.size})"
      opts = { 'Content-Type' => 'application/json' }
      response = http.post(url_parsed.request_uri, data, opts)
    end
    Rails.logger.info "Response: request=#{url} response_status=#{response.class.name} response_code=#{response.code} message_key=#{response.message} body=#{response.body}"

    response
  end
end
