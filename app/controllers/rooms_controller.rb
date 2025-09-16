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
  before_action :setup_consumer_configs, only: %i[launch]

  before_action :find_room, except: %i[launch close]
  before_action :validate_session_token_and_restore_session, only: %i[recording_playback]
  before_action :validate_room, except: %i[launch close]
  before_action :find_user
  before_action :find_app_launch, only: %i[launch]
  before_action :fetch_moodle_cmid, only: %i[launch]
  before_action :setup_moodle_groups, only: %i[launch]
  before_action :set_group_variables, only: %i[show meetings]
  before_action :set_institution_guid, except: %i[launch close]

  before_action only: %i[show launch] do
    authorize_user!(:show, @room)
  end
  before_action only: %i[edit update recording_publish recording_unpublish
                         recording_update recording_delete] do
    authorize_user!(:edit, @room)
  end

  # GET /rooms/1
  def show
    respond_to do |format|
      @room.update_recurring_meetings
      @scheduled_meetings = @room.scheduled_meetings.active

      if @room.moodle_group_select_enabled?
        @scheduled_meetings = @scheduled_meetings.where(moodle_group_id: Rails.cache.read("#{@app_launch.nonce}/current_group_id"))
      end

      @scheduled_meetings = @scheduled_meetings.order(:start_at).page(params[:page])

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
    if @room.moodle_group_select_enabled?
      options['meta_bbb-moodle-group-id'] = Rails.cache.read("#{@app_launch.nonce}/current_group_id")
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

  # GET /rooms/:id/safari_close
  # A page with a button to return to the room's scheduled meetings
  # Users of Safari join meetings in the same tab, so they need some way to return
  def safari_close
    render :safari_close
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

  def eduplay
    @recording = get_recordings(@room, recordID: params['record_id']).first.first
    eduplay_token = EduplayToken.find_by(user_uid: @user.uid)
    return_to = meetings_room_path(@room, filter: params[:filter])

    if eduplay_token.token.present? && eduplay_token.expires_at > Time.now + 30.minutes
      Rails.logger.info "EduplayToken #{eduplay_token}"
      @eduplay_token = eduplay_token.token
      api = Mconf::Eduplay::API.new(eduplay_token.token)
      @channels = api.get_channels
    else
      eduplay_token&.destroy
      @status = 500
      @layout = false
      render 'errors/error' and return
    end

    render "rooms/eduplay"
  end

  def eduplay_upload
    eduplay_token = EduplayToken.find_by(user_uid: @user.uid)
    api = Mconf::Eduplay::API.new(eduplay_token.token)

    if params['channel'] == 'new_channel'
      Rails.logger.info "Creating new channel (name=#{params['channel_name']}, public=#{params['channel_public']}, tags=#{params['channel_tags']})"
      new_channel = api.create_channel(params['channel_name'], params['channel_public'].to_i, params['channel_tags'].split(','))
      if new_channel['result'].present?
        params['channel'] = new_channel['result']
      else
        Rails.logger.error "Error creating new channel: #{new_channel.inspect}"
        flash[:error] = t('meetings.recording.eduplay.errors.error_creating_channel')
        redirect_to(meetings_room_path(@room, filter: params[:filter])) and return
      end
    end

    uploaded_thumbnail = nil
      if params['thumbnail_option'] != 'default'
        uploaded_file = params['image']

        if uploaded_file.present? && uploaded_file.content_type.start_with?('image/') && uploaded_file.size <= 4.megabytes
          tmp_dir = Rails.root.join('tmp/uploads')
          FileUtils.mkdir_p(tmp_dir)
  
          filename = "#{SecureRandom.uuid}_#{uploaded_file.original_filename}"
          filepath = tmp_dir.join(filename)

          File.open(filepath, 'wb') do |file|
            file.write(uploaded_file.read)
          end

          uploaded_thumbnail = [filepath.to_s, uploaded_file.content_type]
        end
      end

    default_tags = Rails.configuration.eduplay_default_tags
    form_tags = params['tags'].split(',')

    video_data = {
      channel_id: params['channel'].to_i,
      title: params['title'],
      description: params['description'],
      public: params['public'].to_i,
      video_password: params['video_password'],
      tags: default_tags | form_tags,
      thumbnail: uploaded_thumbnail,
    }

    UploadRecordingToEduplayJob.perform_later(@room, params['record_id'], video_data, @user.as_json.symbolize_keys)

    # Creates a new EduplayUpload object
    eduplay_upload = EduplayUpload.new(recording_id: params['record_id'], user_uid: @user.uid)
    eduplay_upload.save
    flash[:notice] = t('meetings.recording.eduplay.success')
    redirect_to(meetings_room_path(@room, filter: params[:filter]))
  end

  def eduplay_auth
    eduplay_token = EduplayToken.find_by(user_uid: @user.uid)
    if params['access_token'].present?
      if eduplay_token.nil?
        eduplay_token = EduplayToken.create!(user_uid: @user.uid, token: params['access_token'], expires_at: params['expires_at'])
        Rails.logger.info "EduplayToken #{eduplay_token} created"
      else
        eduplay_token.update(token: params['access_token'], expires_at: params['expires_at'])
        Rails.logger.info "EduplayToken #{eduplay_token} updated (token and expires_at)"
      end
    elsif eduplay_token.nil?
      Rails.logger.warn "EduplayToken not found for user_uid=#{@user.uid} and access_token was not informed"
      flash[:notice] = t('meetings.recording.eduplay.error')
      redirect_to(meetings_room_path(@room, filter: params[:filter])) and return
    end

    Rails.logger.info "Successful auth with EduplayToken #{eduplay_token}"
    redirect_to(eduplay_path(@room, record_id: params['record_id']))
  end

  # GET	/rooms/:id/recording/:record_id/filesender
  def filesender
    filesender_token = FilesenderToken.find_by(user_uid: @user.uid)
    if filesender_token.nil?
      flash[:notice] = t('default.filesender.error')
      redirect_to(meetings_room_path(@room)) and return
    end

    if filesender_token.expires_at.nil? || filesender_token.expires_at < Time.now
      new_token = Mconf::Filesender::API.refresh_token(filesender_token.refresh_token)

      if new_token['error'].present?
        flash[:notice] = t('default.filesender.error')
        redirect_to(meetings_room_path(@room)) and return
      end

      filesender_token.update(token: new_token['access_token'], refresh_token: new_token['refresh_token'],
                              expires_at: Time.now - 24.hours + new_token['expires_in'].to_i)
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
        FilesenderToken.create!(user_uid: @user.uid, token: params['access_token'],
                                refresh_token: params['refresh_token'], expires_at: params['expires_at'])
      else
        old_filesender_token.update(token: params['access_token'], refresh_token: params['refresh_token'], expires_at: params['expires_at'])
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
      moodle_groups = Rails.cache.read("#{@app_launch.nonce}/moodle_groups")
      if moodle_groups.nil? || moodle_groups[:all_groups].nil?
        Rails.logger.error "[nonce: #{@app_launch.nonce}, action: set_current_group_on_session] Error fetching Moodle groups from cache " \
        "(moodle_groups: #{moodle_groups})"
        set_error('room', 'cache_read_error', 500)
        respond_with_error(@error)
        return
      end

      groups_ids_list = moodle_groups[:all_groups].keys
      if groups_ids_list.include?(params[:group_id].to_i)
        Rails.cache.write("#{@app_launch.nonce}/current_group_id", params[:group_id].to_i)
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
    @app_launch = AppLaunch.create_with(room_handler: handler)
                   .find_or_create_by(nonce: launch_nonce) do |launch|
      launch.update(
        params: launch_params,
        omniauth_auth: session['omniauth_auth']['bbbltibroker'],
        expires_at: expires_at
      )
    end
    Rails.logger.info "Saved the AppLaunch nonce=#{@app_launch.nonce} room_handler=#{@app_launch.room_handler}"

    # Use this data only during the launch
    # From now on, take it from the AppLaunch
    session.delete('omniauth_auth')

    # Create/update the room
    local_room_params = @app_launch.room_params
    @room = Room.create_with(local_room_params)
              .find_or_create_by(handler: local_room_params[:handler])
    @room.update(local_room_params) if @room.present?

    # Create the user session
    # Keep it as small as possible, most of the data is in the AppLaunch
    set_room_session(
      @room, { launch: launch_nonce }
    )
  end

  def setup_consumer_configs
    custom_params = @app_launch.custom_params
    return if custom_params.nil?

    # Create or update the ConsumerConfig with custom_params
    @consumer_config = ConsumerConfig.find_or_create_by(key: @app_launch.consumer_key)
    @consumer_config.update(
      set_duration: custom_params['set_duration'],
      download_presentation_video: custom_params['download_presentation_video'],
      message_reference_terms_use: custom_params['message_reference_terms_use'],
      force_disable_external_link: custom_params['force_disable_external_link'],
      external_widget: custom_params['external_widget'],
      external_disclaimer: custom_params['external_disclaimer'],
      external_context_url: custom_params['external_context_url'],
      institution_guid: custom_params['institution_guid']
    )
    Rails.logger.info "[setup_consumer_configs] ConsumerConfig created/updated with key=#{@consumer_config.key}, " \
    "params=#{custom_params.except('bbb', 'moodle', 'brightspace')}"

    # Create or update the ConsumerConfigServer
    if custom_params.key?('bbb')
      bbb_configs = custom_params['bbb']
      consumer_config_server = ConsumerConfigServer.find_or_create_by(consumer_config: @consumer_config)
      consumer_config_server.update(
        endpoint: bbb_configs['url'],
        internal_endpoint: bbb_configs['internal_url'],
        secret: bbb_configs['secret']
      )
      Rails.logger.info "[setup_consumer_configs] ConsumerConfigServer created/updated, params=#{bbb_configs}"
    else
      destroyed = @consumer_config.server&.destroy
      Rails.logger.info "[setup_consumer_configs] No params received for ConsumerConfigServer" \
      "#{destroyed ? ', destroyed the existing one' : ''}"
    end

    # Create or update the MoodleToken
    if custom_params.key?('moodle')
      moodle_configs = custom_params['moodle']
      moodle_token = MoodleToken.find_or_create_by(consumer_config: @consumer_config)
      moodle_token.update(
        url: moodle_configs['url'],
        token: moodle_configs['token'],
        group_select_enabled: moodle_configs['group_select_enabled'],
        show_all_groups: moodle_configs['show_all_groups']
      )
      Rails.logger.info "[setup_consumer_configs] MoodleToken created/updated, params=#{moodle_configs}"
    else
      destroyed = @consumer_config.moodle_token&.destroy
      Rails.logger.info '[setup_consumer_configs] No params received for MoodleToken' \
      "#{destroyed ? ', destroyed the existing one' : ''}"
    end

    # Create or update the ConsumerConfigBrightspaceOauth
    if custom_params.key?('brightspace')
      brightspace_configs = custom_params['brightspace']
      brightspace_oauth = ConsumerConfigBrightspaceOauth.find_or_create_by(consumer_config: @consumer_config)
      brightspace_oauth.update(
        url: brightspace_configs['oauth_url'],
        client_id: brightspace_configs['oauth_client_id'],
        client_secret: brightspace_configs['oauth_client_secret'],
        scope: brightspace_configs['oauth_scopes']
      )
      Rails.logger.info "[setup_consumer_configs] ConsumerConfigBrightspaceOauth created/updated, " \
      "params=#{brightspace_configs}"
    else
      destroyed = @consumer_config.brightspace_oauth&.destroy
      Rails.logger.info "[setup_consumer_configs] No params received for ConsumerConfigBrightspaceOauth" \
      "#{destroyed ? ', destroyed the existing one' : ''}"
    end
  end

  def fetch_moodle_cmid
    return unless @room.moodle_token
    # the `resource_link_id` provided by Moodle is the `instance_id` of the activity.
    # We use it to fetch the activity data, from where we get its `cmid` (course module id)
    activity_data = Moodle::API.get_activity_data(
      @room.moodle_token,
      @app_launch.params['resource_link_id'],
      { nonce: @app_launch.nonce }
    )
    if activity_data.nil?
      Rails.logger.warn "[fetch_moodle_cmid] Could not get the data from activity" \
                        " instance_id=#{@app_launch.params['resource_link_id']}"
      return
    end
    # store the activity's cmid in the app_launch for later use
    # (e.g. when checking groupmode or creating calendar events)
    @app_launch.update(params: @app_launch.params.merge('cmid' => activity_data['id']))
  end

  # Initial setup for Moodle groups feature:
  # - check for necessary functions
  # - fetch groups data and store it in the cache
  def setup_moodle_groups
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

      # Validates the configured Moodle Token and checks for missing functions
      # - token_validation_result[:valid_token] indicates if the token is valid (`true`) or not (`false`)
      # - token_validation_result[:missing_functions] has a list of missing function (if there is any)
      token_validation_result = Moodle::API.validate_token_and_check_missing_functions(moodle_token, wsfunctions, {nonce: @app_launch.nonce})
      if token_validation_result[:valid_token] == false
        Rails.logger.error 'Invalid or not found Moodle token'
        set_error('room', 'moodle_invalid_token', 500)
        @error[:explanation] = t("error.room.moodle_invalid_token.explanation")
        respond_with_error(@error)
        return
      elsif token_validation_result[:missing_functions].any?
        Rails.logger.error 'A function required for the groups feature is not configured in the Moodle service'
        set_error('room', 'moodle_token_function_missing', :forbidden)
        @error[:explanation] = t("error.room.moodle_token_function_missing.explanation", missing_functions: token_validation_result[:missing_functions])
        respond_with_error(@error)
        return
      end

      # check if we have the activity's cmid stored in the app_launch (from `fetch_moodle_cmid`),
      # if not, respond with error
      if @app_launch.params['cmid'].nil?
        Rails.logger.error '[setup_moodle_groups] The \'cmid\' is missing from app_launch params'
        set_error('room', 'moodle_activity_not_found', :forbidden)
        respond_with_error(@error)
        return
      end

      # testing if the activity has its groupmode configured for separate groups (1)
      # or visible groups (2)
      groupmode = Moodle::API.get_groupmode(moodle_token, @app_launch.params['cmid'], {nonce: @app_launch.nonce})
      if groupmode == 0 || groupmode.nil?
        Rails.logger.error 'The Moodle activity has an invalid groupmode configured'
        set_error('room', 'moodle_invalid_groupmode', :forbidden)
        respond_with_error(@error)
        return
      end

      Rails.logger.info "Moodle groups are configured for this session (#{@app_launch.nonce})"

      user_groups = Moodle::API.get_user_groups(moodle_token, @user.uid, @app_launch.context_id, {nonce: @app_launch.nonce})

      # Example of the final hash stored in the cache for a user that belongs to groups 1 and 2,
      # from a course that has groups 1, 2 and 3
      # moderator, show_all_groups=true   {all_groups: {1: 'abc', 2: 'def', 3: 'ghi'}, user_groups: {1: 'abc', 2: 'def'}}
      # moderator, show_all_groups=false 	{all_groups: {1: 'abc', 2: 'def'}}
      # student		 	                      {all_groups: {1: 'abc', 2: 'def'}}
      #
      # moderators may need to see all groups, depending on the moodle_token's `show_all_groups` flag
      if @user.moderator?(Abilities.moderator_roles) && @room.show_all_moodle_groups?
        # Gets all course groups except the default 'All Participants' group (id 0);
        all_groups = Moodle::API.get_course_groups(moodle_token, @app_launch.context_id, {nonce: @app_launch.nonce})
                    .delete_if{ |element| element['id'] == "0" }
        if all_groups.empty?
          Rails.logger.error "There are no groups registered in this Moodle course"
          set_error('room', 'moodle_course_without_groups', :forbidden)
          respond_with_error(@error)
          return
        end
        all_groups_hash = all_groups.collect{ |g| g.slice('id', 'name').values }.to_h

        if user_groups.any?
          # user_groups_hash => {'1': 'Grupo A', '2': 'Grupo B'}
          user_groups_hash = user_groups.collect{ |g| g.slice('id', 'name').values }.to_h
          current_group_id = user_groups.first['id']
        else
          user_groups_hash = {'no_groups': 'Você não pertence a nenhum grupo'}
          current_group_id = all_groups.first['id']
        end

        Rails.cache.write("#{@app_launch.nonce}/moodle_groups",
          all_groups: all_groups_hash,
          user_groups: user_groups_hash
        )
      else
        # non-moderators only see groups they belong to
        if user_groups.any?
          user_groups_hash = user_groups.collect{ |g| g.slice('id', 'name').values }.to_h
          current_group_id = user_groups.first['id']
        else
          Rails.logger.error "The user #{@user.uid} doesn't belong to any group in the Moodle course"
          set_error('room', 'moodle_user_without_groups', :forbidden)
          respond_with_error(@error)
          return
        end

        Rails.cache.write("#{@app_launch.nonce}/moodle_groups", all_groups: user_groups_hash)
      end

      Rails.cache.write("#{@app_launch.nonce}/current_group_id", current_group_id)
    end
  rescue Moodle::UrlNotFoundError => e
    set_error('room', 'moodle_url_not_found', 500)
    respond_with_error(@error)
    return
  rescue Moodle::TimeoutError => e
    uri = @room.moodle_token ? URI.parse(@room.moodle_token.url).host : ''
    set_error('room', 'moodle_timeout_error', 500)
    @error[:explanation] = t("error.room.moodle_timeout_error.explanation", server_url: uri)
    respond_with_error(@error)
    return
  rescue Moodle::RequestError => e
    set_error('room', 'moodle_request_error', 500)
    respond_with_error(@error)
    return
  end

  # Set the variables expected by the `group_select` partial
  def set_group_variables
    if @room.moodle_group_select_enabled?
      @current_group_id = Rails.cache.read("#{@app_launch.nonce}/current_group_id")
      moodle_groups = Rails.cache.read("#{@app_launch.nonce}/moodle_groups")
      all_groups_hash = moodle_groups.to_h[:all_groups]
      # check for errors fetching from cache
      if @current_group_id.nil? || moodle_groups.nil? || all_groups_hash.nil?
        Rails.logger.error "[nonce: #{@app_launch.nonce}] Error fetching Moodle groups from cache " \
        "(current_group_id: #{@current_group_id}, moodle_groups: #{moodle_groups})"
        set_error('room', 'cache_read_error', 500)
        respond_with_error(@error)
        return
      end

      if @user.moderator?(Abilities.moderator_roles) && @room.show_all_moodle_groups?
        user_groups_hash = moodle_groups[:user_groups]
        # check for errors fetching from cache
        if user_groups_hash.nil?
          Rails.logger.error "[nonce: #{@app_launch.nonce}] Error fetching user_groups from cache " \
          "(current_group_id: #{@current_group_id}, moodle_groups: #{moodle_groups})"
          set_error('room', 'cache_read_error', 500)
          respond_with_error(@error)
          return
        end

        other_groups = all_groups_hash.reject { |key, _| user_groups_hash.key?(key) }
        if other_groups.empty?
          other_groups = {'no_groups': 'Você pertence a todos os grupos'}
        end
        @group_select = {"Grupos que participo": user_groups_hash.invert, "Outros grupos": other_groups.invert}
      else
        @group_select = all_groups_hash.invert
      end

      @current_group_name = all_groups_hash[@current_group_id]
    end
  end

  def fetch_external_context(launch_params)
    app_launch = AppLaunch.new(params: launch_params)
    ext_context_url = app_launch.custom_params['external_context_url']

    # will only try to get an external context/handler if the `external_context_url` custom_param is present
    return true, nil if ext_context_url.blank? # proceed without a handler

    # this is a temporary user in case we are responding the request here and we need it (at least
    # the locale we need to set, even for error pages)
    @user = User.new(app_launch.user_params)
    set_current_locale

    # The API has different endpoints for teachers and students
    base = ext_context_url.match(/.*\/context/).to_s
    # ext_context_url = "http://<lti-context-api-host>/context/rooms"
    # base = "http://<lti-context-api-host>/context"
    ext_context_url = @user.moderator?(Abilities.moderator_roles) ? "#{base}/teacher/rooms" : "#{base}/student/rooms"

    Rails.logger.info "The consumer key=#{app_launch.consumer_key} is configured to " \
    "fetch the context/handler from url=#{ext_context_url}"

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
      @launch_nonce = params['launch_nonce']
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
