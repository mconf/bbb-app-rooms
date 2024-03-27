# frozen_string_literal: true

require 'net/http'
require 'user'
require 'bbb_api'
require './lib/mconf/eduplay'
require './lib/mconf/filesender'

class RoomsController < ApplicationController
  include ApplicationHelper
  include MeetingsHelper
  include BbbApi
  include BbbAppRooms

  before_action -> {authenticate_with_oauth! :bbbltibroker},
    only: :launch, raise: false
  before_action :set_launch_room, only: %i[launch]

  before_action :find_room, except: %i[launch close]
  before_action :validate_room, except: %i[launch close]
  before_action :find_user
  before_action :find_app_launch, only: %i[launch]
  before_action :set_user_groups_on_session, only: %i[launch]
  before_action :set_room_title, only: :show
  before_action :set_group_variables, only: %i[show meetings]

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
    # with groups configured, non-moderators only see meetings that belong to the current
    # selected group
    if @room.moodle_group_select_enabled? && !@user.moderator?(Abilities.moderator_roles)
      options['meta_bbb-moodle-group-id'] = get_from_room_session(@room, 'current_group_id')
    end

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

    # Creates a new EduplayUpload object
    eduplay_upload = EduplayUpload.new(recording_id: params['record_id'], user_uid: @user.uid)
    eduplay_upload.save

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

  # POST /rooms/1/set_current_group_on_session
  # expected params: [:group_id, :redir_url]
  def set_current_group_on_session
    if @room.moodle_group_select_enabled? && params[:group_id].present?
      groups_ids_list = get_from_room_session(@room, 'user_groups').keys
      if groups_ids_list.include?(params[:group_id])
        add_to_room_session(@room, 'current_group_id', params[:group_id])
      else
        Rails.logger.warn "User #{@user.uid} tried to set an invalid group id: #{params[:group_id]}"
        flash[:error] = t('default.room.error.invalid_group')
      end
    end

    redirect_to params[:redir_url]
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

    # check if we need to fetch the context/handler from an external URL
    proceed, handler = fetch_external_context(launch_params)
    return unless proceed

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

  # Adds the user first group ID to the session if the grouping
  # feature is enabled.
  # Adds the formatted user groups to the session
  # Example:
  # current_group_id: 1
  # user_groups: {'1': 'Grupo A', '2': 'Grupo B'}
  def set_user_groups_on_session
    if @room.moodle_group_select_enabled?
      moodle_token = @room.moodle_token
      Rails.logger.info "Moodle token #{moodle_token.token} found, group select is enabled"
      # testing if the token is configured with the necessary functions
      wsfunctions = [
        'core_group_get_activity_groupmode',
        'core_group_get_course_user_groups',
        'core_course_get_course_module_by_instance',
        'core_group_get_course_groups'
      ]
      
      unless Moodle::API.check_token_functions(moodle_token, wsfunctions)
        Rails.logger.error 'A function required for the groups feature is not configured in Moodle'
        set_error('room', 'moodle_token_misconfigured', :forbidden)
        respond_with_error(@error)
        return
      end

      # the `resource_link_id` provided by Moodle is the `instance_id` of the activity.
      # We use it to fetch the activity data, from where we get its `cmid` (course module id)
      # to fetch the effective groupmode configured on the activity
      activity_data = Moodle::API.get_activity_data(moodle_token, @app_launch.params['resource_link_id'])
      if activity_data.nil?
        Rails.logger.error "Could not find the necessary data for this activity (instance_id: #{@app_launch.params['resource_link_id']})"
        set_error('room', 'moodle_token_misconfigured', :forbidden)
        respond_with_error(@error)
        return
      end

      groupmode = Moodle::API.get_groupmode(moodle_token, activity_data['id'])
      # testing if the activity has its groupmode configured for separate groups (1)
      # or visible groups (2)
      if groupmode == 0 || groupmode.nil?
        Rails.logger.error 'The Moodle activity has an invalid groupmode configured'
        set_error('room', 'moodle_token_misconfigured', :forbidden)
        respond_with_error(@error)
        return
      end

      Rails.logger.info "Moodle groups are configured for this session (#{@app_launch.nonce})"

      if @user.moderator?(Abilities.moderator_roles)
        # Gets all course groups except the default 'All Participants' group (id 0)
        groups = Moodle::API.get_course_groups(moodle_token, @app_launch.context_id)
                .delete_if{ |element| element['id'] == "0" }
      else
        groups = Moodle::API.get_user_groups(moodle_token, @user.uid, @app_launch.context_id)
      end

      if groups.any?
        groups_hash = groups.collect{ |g| g.slice('id', 'name').values }.to_h
        current_group_id = groups.first['id']
      else
        groups_hash = {'no_groups': 'Você não pertence a nenhum grupo'}
        current_group_id = 'no_groups'
      end

      add_to_room_session(@room, 'current_group_id', current_group_id)
      add_to_room_session(@room, 'user_groups', groups_hash)
    end
  end

  # Set the variables expected by the `group_select` partial
  def set_group_variables
    if @room.moodle_group_select_enabled?
      @groups_hash = get_from_room_session(@room, 'user_groups')
      @group_select = @groups_hash.invert
      @current_group_id = get_from_room_session(@room, 'current_group_id')
    end
  end

  def set_room_title
    if @app_launch&.coc_launch?
      @title = @room.name
      @subtitle = @room.description
    end
  end

  def fetch_external_context(launch_params)
    launch_nonce = params['launch_nonce']

    # this is a temporary user in case we are responding the request here and we need it (at least
    # the locale we need to set, even for error pages)
    user_params = AppLaunch.new(params: launch_params).user_params
    @user = BbbAppRooms::User.new(user_params)
    set_current_locale

    # will only try to get an external context/handler if the ConsumerConfig is configured to do so
    if launch_params.key?('custom_params') && launch_params['custom_params'].key?('oauth_consumer_key')
      consumer_key = launch_params['custom_params']['oauth_consumer_key']
      if consumer_key.present?
        ext_context_url = ConsumerConfig.find_by(key: consumer_key)&.external_context_url
      end
    end
    return true, nil if ext_context_url.blank? # proceed without a handler

    Rails.logger.info "The consumer is configured to use an API to fetch the context/handler consumer_key=#{consumer_key} url=#{ext_context_url}"

    Rails.logger.info "Making a request to an external API to define the context/handler url=#{ext_context_url}"
    begin
      response = send_request(ext_context_url, launch_params)
      # example response:
      # [
      #   {
      #      "handler": "82af745030b9e1394815e61184d50fd25dfe884a",
      #      "name": "STRW2S/Q16.06",
      #      "uuid": "a9a2689a-1e27-4ce8-aa91-ca488620bb89"
      #   }
      # ]
      handlers = JSON.parse(response.body)
      Rails.logger.warn "Got the following contexts from the API: #{handlers.inspect}"
    rescue JSON::ParserError => error
      Rails.logger.warn "Error parsing the external context API's response"
      set_error('room', 'external_context_parse_error', 500)
      respond_with_error(@error)
      return false, nil
    end
    # in case the response is anything other than an array, consider it empty
    handlers = [] unless handlers.is_a?(Array)

    # if the handler was already set, try to use it
    # this will happen in the 2nd step, after the user selects a handler/room to access
    selected_handler = params['handler']
    unless selected_handler.blank?
      Rails.logger.info "Found a handler in the params, will try to use it handler=#{selected_handler}"

      if handlers.find{ |h| h['handler'] == selected_handler }.nil?
        Rails.logger.info "The handler found is NOT allowed, will not use it handler=#{selected_handler}"
        set_error('room', 'external_context_invalid_handler', :forbidden)
        respond_with_error(@error)
        return false, nil
      else
        Rails.logger.info "The handler found is allowed, will use it handler=#{selected_handler}"
        return true, selected_handler # proceed with a handler
      end
    end

    if handlers.size == 0
      Rails.logger.warn "Couldn't define a handler using the external request"
      set_error('room', 'external_context_no_handler', :forbidden)
      respond_with_error(@error)
      return false, nil
    elsif handlers.size > 1
      @handlers = handlers
      @launch_nonce = launch_nonce
      respond_to do |format|
        format.html { render 'rooms/external_context_selector' }
      end
      return false, nil
    else
      handler = handlers.first['handler']
      Rails.logger.info "Defined a handler using the external request handler=#{handler}"
      return true, handler
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
