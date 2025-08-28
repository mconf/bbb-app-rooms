# coding: utf-8
# frozen_string_literal: true

require 'user'
require 'bbb_api'

class ScheduledMeetingsController < ApplicationController
  include ApplicationHelper
  include BbbApi
  include BbbAppRooms
  include GuestUserModule

  # actions that can be accessed without a session, without the LTI launch
  open_actions = %i[external wait join running updateMeetingData guest_logout]

  # validate the room/session only for routes that are not open
  before_action :find_room
  before_action :validate_room, except: open_actions
  before_action :validate_session_token_and_restore_session, only: :join
  before_action :find_user
  before_action :find_app_launch, only: %i[create update destroy]
  before_action :set_institution_guid

  before_action :find_scheduled_meeting, only: (%i[edit update destroy] + open_actions)
  before_action :validate_scheduled_meeting, only: (%i[edit update destroy] + open_actions)

  before_action only: %i[join external wait] do
    authorize_user!(:show, @scheduled_meeting) if @user.present?
  end
  before_action only: %i[new create edit update destroy] do
    authorize_user!(:edit, @room)
  end

  before_action :set_blank_repeat_as_nil, only: %i[create update]

  def new
    @scheduled_meeting = ScheduledMeeting.new(@room.attributes_for_meeting)
    @scheduled_meeting.create_moodle_calendar_event = true
    if @room.moodle_group_select_enabled?
      current_group_id = Rails.cache.read("#{@app_launch.nonce}/current_group_id")
      moodle_groups = Rails.cache.read("#{@app_launch.nonce}/moodle_groups")
      if current_group_id.nil? || moodle_groups.nil?
        Rails.logger.warn "[nonce: #{@app_launch.nonce}, action: new] Attempt #1 fetching Moodle groups from cache " \
        "(current_group_id: #{current_group_id}, moodle_groups: #{moodle_groups}). Trying again"

        current_group_id = Rails.cache.read("#{@app_launch.nonce}/current_group_id")
        moodle_groups = Rails.cache.read("#{@app_launch.nonce}/moodle_groups")
        if current_group_id.nil? || moodle_groups.nil?
          Rails.logger.error "[nonce: #{@app_launch.nonce}, action: new] Attempt #2 fetching Moodle groups from cache " \
          "(current_group_id: #{current_group_id}, moodle_groups: #{moodle_groups})"
          set_error('room', 'cache_read_error', 500)
          respond_with_error(@error)
          return
        end
      end

      all_groups_hash = moodle_groups[:all_groups]
      @current_group_name = all_groups_hash.to_h[current_group_id]
      if all_groups_hash.nil? || @current_group_name.nil?
        Rails.logger.error "[nonce: #{@app_launch.nonce}, action: new] Error fetching group_name from cache " \
        "(current_group_id: #{current_group_id}, all_groups: #{all_groups_hash}, group_name: #{@current_group_name})"
        set_error('room', 'cache_read_error', 500)
        respond_with_error(@error)
        return
      end
    end
  end

  def create
    respond_to do |format|
      # use the attributes from the room as the default
      # then override with the permitted params incoming from the view
      @scheduled_meeting = @room.scheduled_meetings.new(
        @room.attributes_for_meeting.merge(
          scheduled_meeting_params(@room)
        )
      )

      config = ConsumerConfig.find_by(key: @room.consumer_key)
      @scheduled_meeting.disable_external_link = true if config&.force_disable_external_link

      if @room.moodle_group_select_enabled?
        current_group_id = Rails.cache.read("#{@app_launch.nonce}/current_group_id")
        moodle_groups = Rails.cache.read("#{@app_launch.nonce}/moodle_groups")
        if current_group_id.nil? || moodle_groups.nil?
          Rails.logger.warn "[nonce: #{@app_launch.nonce}, action: create] Attempt #1 fetching Moodle groups from cache " \
          "(current_group_id: #{current_group_id}, moodle_groups: #{moodle_groups}). Trying again"

          current_group_id = Rails.cache.read("#{@app_launch.nonce}/current_group_id")
          moodle_groups = Rails.cache.read("#{@app_launch.nonce}/moodle_groups")
          if current_group_id.nil? || moodle_groups.nil?
            Rails.logger.error "[nonce: #{@app_launch.nonce}, action: create] Attempt #2 fetching Moodle groups from cache " \
            "(current_group_id: #{current_group_id}, moodle_groups: #{moodle_groups})"
            @scheduled_meeting.errors.add(:moodle_group_data_not_found, t('scheduled_meetings.error.moodle_group_data_not_found'))
            render :new and return
          end
        end

        all_groups_hash = moodle_groups[:all_groups]
        group_name = all_groups_hash.to_h[current_group_id]
        if all_groups_hash.nil? || group_name.nil?
          Rails.logger.error "[nonce: #{@app_launch.nonce}, action: create] Error fetching group_name from cache " \
          "(current_group_id: #{current_group_id}, all_groups: #{all_groups_hash}, group_name: #{group_name})"
          flash[:error] = t('scheduled_meetings.error.moodle_group_data_not_found')
          redirect_to room_path(@room) and return
        end

        @scheduled_meeting.moodle_group_id = current_group_id.to_i
        @scheduled_meeting.moodle_group_name = group_name
      end

      if @scheduled_meeting.duration.zero?
        @scheduled_meeting[:duration] =
          ScheduledMeeting.convert_time_to_duration(params[:scheduled_meeting][:custom_duration])
      end

      valid_start_at = validate_start_at(@scheduled_meeting)
      if valid_start_at
        @scheduled_meeting.set_dates_from_params(params[:scheduled_meeting])
      else
        @scheduled_meeting.errors.add(:start_at, t('default.scheduled_meeting.error.invalid_start_at'))
      end

      room_session = get_room_session(@room)
      @scheduled_meeting.created_by_launch_nonce = room_session['launch'] if room_session.present?
      if valid_start_at && @scheduled_meeting.save
        if params[:scheduled_meeting][:create_moodle_calendar_event] == '1' &&
        @room.can_create_moodle_calendar_event
          moodle_token = @room.consumer_config.moodle_token
          if @scheduled_meeting.recurring?
            CreateRecurringEventsInMoodleCalendarJob.perform_later(moodle_token, @scheduled_meeting, @app_launch.context_id, {nonce: @app_launch.nonce})
          else
            unless Moodle::API.create_calendar_event(moodle_token, @scheduled_meeting.hash_id, @scheduled_meeting, @app_launch.context_id, {nonce: @app_launch.nonce})
              flash[:error] = t('scheduled_meetings.error.moodle_create_calendar_event')
            end
          end
        end
        format.html do
          return_path = room_path(@room), { notice: t('default.scheduled_meeting.created') }
          redirect_if_brightspace(return_path) || redirect_to(*return_path)
        end
      else
        format.html { render :new }
      end
    end
  end

  def edit
  end

  def update
    old_repeat = @scheduled_meeting.repeat
    respond_to do |format|
      valid_start_at = validate_start_at(@scheduled_meeting)
      if valid_start_at
        @scheduled_meeting.set_dates_from_params(params[:scheduled_meeting])
      else
        @scheduled_meeting.errors.add(:start_at, t('default.scheduled_meeting.error.invalid_start_at'))
      end

      if params[:scheduled_meeting]['duration'].to_i.zero?
        params[:scheduled_meeting]['duration'] =
          ScheduledMeeting.convert_time_to_duration(params[:scheduled_meeting][:custom_duration])
      end

      if valid_start_at && @scheduled_meeting.update(scheduled_meeting_params(@room))
        moodle_calendar_events_ids = MoodleCalendarEvent.where(scheduled_meeting_hash_id: @scheduled_meeting.hash_id).pluck(:event_id)
        has_become_recurring = old_repeat.nil? && @scheduled_meeting.recurring?
        has_lost_recurrence = !old_repeat.nil? && @scheduled_meeting.repeat.nil?
        has_changed_recurrence = old_repeat != @scheduled_meeting.repeat
        changes = @scheduled_meeting.previous_changes
        tracked_attrs = ['name', 'start_at', 'description']

        if @room.can_create_moodle_calendar_event && @room.can_delete_moodle_calendar_event && moodle_calendar_events_ids.any?
          moodle_token = @room.consumer_config.moodle_token
          case
          when has_become_recurring
            Moodle::API.delete_calendar_event(moodle_token, moodle_calendar_events_ids.first, @app_launch.context_id, { nonce: @app_launch.nonce })
            MoodleCalendarEvent.find_by(event_id: moodle_calendar_events_ids.first).destroy
            CreateRecurringEventsInMoodleCalendarJob.perform_later(moodle_token, @scheduled_meeting, @app_launch.context_id, { nonce: @app_launch.nonce })
          when has_lost_recurrence
            DeleteRecurringEventsInMoodleCalendarJob.perform_later(moodle_token, moodle_calendar_events_ids, @app_launch.context_id, {nonce: @app_launch.nonce})
            unless Moodle::API.create_calendar_event(moodle_token, @scheduled_meeting.hash_id, @scheduled_meeting, @app_launch.context_id, {nonce: @app_launch.nonce})
              flash[:error] = t('scheduled_meetings.error.moodle_create_calendar_event')
            end
          when has_changed_recurrence || (changes.keys & tracked_attrs).any?
            if @scheduled_meeting.recurring?
              DeleteRecurringEventsInMoodleCalendarJob.perform_later(moodle_token, moodle_calendar_events_ids, @app_launch.context_id, {nonce: @app_launch.nonce})
              CreateRecurringEventsInMoodleCalendarJob.perform_later(moodle_token, @scheduled_meeting, @app_launch.context_id, { nonce: @app_launch.nonce })
            else
              Moodle::API.delete_calendar_event(moodle_token, moodle_calendar_events_ids.first, @app_launch.context_id, { nonce: @app_launch.nonce })
              MoodleCalendarEvent.find_by(event_id: moodle_calendar_events_ids.first).destroy
              unless Moodle::API.create_calendar_event(moodle_token, @scheduled_meeting.hash_id, @scheduled_meeting, @app_launch.context_id, {nonce: @app_launch.nonce})
                flash[:error] = t('scheduled_meetings.error.moodle_create_calendar_event')
              end
            end
          end
        end

        format.html do
          return_path = room_path(@room), { notice: t('default.scheduled_meeting.updated') }
          redirect_if_brightspace(return_path) || redirect_to(*return_path)
        end
      else
        format.html { render :edit }
      end
    end
  end

  def join
    opts = {}
    if browser.safari? || browser.safari_webapp_mode?
      opts[:logout_url] = @user.present? ? safari_close_room_url(@room) : autoclose_url
      Rails.logger.debug "User's browser is Safari, logout_url: #{opts[:logout_url]}"
    end

    # if there's a user signed in, always use their info
    # only way for a meeting to be created is through here
    if @user.present?
      # Fallback to fetch the Moodle group name from the cache and concatenate it to the meeting name
      # when `moodle_group_name` is blank
      if @room.moodle_group_select_enabled? && @scheduled_meeting.moodle_group_name.blank?
        Rails.logger.info "This scheduled_meeting (#{params[:id]}) has a blank moodle_group_name, fetching it from the cache"
        current_group_id = Rails.cache.read("#{@app_launch.nonce}/current_group_id")
        moodle_groups = Rails.cache.read("#{@app_launch.nonce}/moodle_groups")
        if current_group_id.nil? || moodle_groups.nil?
          Rails.logger.warn "[nonce: #{@app_launch.nonce}, action: join] Attempt #1 fetching Moodle groups from cache " \
          "(current_group_id: #{current_group_id}, moodle_groups: #{moodle_groups}). Trying again"

          current_group_id = Rails.cache.read("#{@app_launch.nonce}/current_group_id")
          moodle_groups = Rails.cache.read("#{@app_launch.nonce}/moodle_groups")
          if current_group_id.nil? || moodle_groups.nil?
            Rails.logger.error "[nonce: #{@app_launch.nonce}, action: join] Attempt #2 fetching Moodle groups from cache " \
            "(current_group_id: #{current_group_id}, moodle_groups: #{moodle_groups})"
            set_error('room', 'cache_read_error', 500)
            respond_with_error(@error)
            return
          end
        end

        all_groups_hash = moodle_groups[:all_groups]
        group_name = all_groups_hash.to_h[current_group_id]
        if all_groups_hash.nil? || group_name.nil?
          Rails.logger.error "[nonce: #{@app_launch.nonce}, action: join] Error fetching group_name from cache " \
          "(current_group_id: #{current_group_id}, all_groups: #{all_groups_hash}, group_name: #{group_name})"
          set_error('room', 'cache_read_error', 500)
          respond_with_error(@error)
          return
        end

        opts[:meeting_name] = "#{@scheduled_meeting.name} - #{group_name}"
      end

      if @room.can_mark_moodle_attendance && @scheduled_meeting.mark_moodle_attendance
        opts["meta_analytics-callback-url"] = moodle_attendance_url(host: Rails.application.config.url_host)
      end

      # make user wait until moderator is in room
      if wait_for_mod?(@scheduled_meeting, @user) && (!mod_in_room?(@scheduled_meeting) ||
        (params[:no_auto_join] == 'true' && device_type? != 'desktop'))
        redirect_to wait_room_scheduled_meeting_path(@room, @scheduled_meeting)
      else
        # notify users if cable is enabled
        if Rails.application.config.cable_enabled
          NotifyRoomWatcherJob.set(wait: 10.seconds).perform_later(@scheduled_meeting)
        end

        # join as moderator (creates the meeting if not created yet)
        res = join_api_url(@scheduled_meeting, @user, opts)
        if res[:can_join?]
          if params[:join_in_app] == 'true'
            direct_join_url = 'br.rnp.conferenciawebmobile://direct-join/' + res[:join_api_url].gsub(/^https?:\/\//, '') + "&meetingName=#{@scheduled_meeting.name}"
            redirect_to direct_join_url
          else
            redirect_to res[:join_api_url]
          end
        else
          flash[:error] = t("default.scheduled_meeting.error.#{res[:messageKey]}")
          redirect_to room_path(@room)
        end
      end

    # no signed in user, expects identification parameters in the url and join
    # the user always as guest
    else
      if params[:first_name].blank? || params[:first_name].strip.blank? ||
         params[:last_name].blank? || params[:last_name].strip.blank?
        redirect_to external_room_scheduled_meeting_path(@room, @scheduled_meeting)
        return
      end

      unless guest_user_signed_in?
        sign_in_guest(params[:first_name], params[:last_name], Time.now + 8.hours)
      end

      current_guest_user

      if !mod_in_room?(@scheduled_meeting)
        redirect_to wait_room_scheduled_meeting_path(
                      @room, @scheduled_meeting,
                      first_name: params[:first_name], last_name: params[:last_name]
                    )
      else
        # join as guest
        name = "#{params[:first_name]} #{params[:last_name]}"
        res = external_join_api_url(@scheduled_meeting, name, "guest_#{@guest[:uid]}", opts)
        if res[:can_join?]
          if params[:join_in_app] == 'true'
            direct_join_url = 'br.rnp.conferenciawebmobile://direct-join/' + res[:join_api_url].gsub(/^https?:\/\//, '') + "&meetingName=#{@scheduled_meeting.name}"
            redirect_to direct_join_url
          else
            redirect_to res[:join_api_url]
          end
        else
          flash[:error] = t("default.scheduled_meeting.error.#{res[:messageKey]}")
          redirect_to external_room_scheduled_meeting_path(@room, @scheduled_meeting)
        end
      end
    end
  end

  def wait
    # no user in the session and no name set, go back to the external join page
    if @user.nil? && (params[:first_name].blank? || params[:last_name].blank?)
      redirect_to external_room_scheduled_meeting_path(@room, @scheduled_meeting)
      return
    end

    # if this flag is set in the session, wait a short while and try to join again
    # this happens when users try to create a meeting that's already being created
    auto = get_from_room_session(@room, 'auto_join')
    if auto.present?
      remove_from_room_session(@room, 'auto_join')
      @auto_join = true
    end

    # users with a session and anonymous users can wait in this page
    # decide here where they will go to when the meeting starts
    if @user.present?
      @full_name = @user.full_name
      @post_to = join_room_scheduled_meeting_path(@room, @scheduled_meeting)
    else
      @full_name = "#{params[:first_name]} #{params[:last_name]}"
      @post_to = join_room_scheduled_meeting_path(
        @room, @scheduled_meeting,
        first_name: params[:first_name], last_name: params[:last_name]
      )
    end
    @is_running = mod_in_room?(@scheduled_meeting)
    @can_join_or_create = join_or_create?
  end

  def external
    # If the external link is disabled, users should get an error
    # if they are not signed in
    config = ConsumerConfig.find_by(key: @room.consumer_key)
    if (@scheduled_meeting.disable_external_link || config&.force_disable_external_link) && @user.blank?
      redirect_to errors_path(404)
    end

    # allow signed in users to use this page, but autofill the inputs
    # and don't let users change them
    if @user.present?
      @first_name = @user.first_name
      @last_name = @user.last_name
    end

    if current_guest_user.present?
      @first_name=@guest[:first_name]
      @last_name=@guest[:last_name]
    end

    @scheduled_meeting.update_to_next_recurring_date

    @is_running = mod_in_room?(@scheduled_meeting)
    @ended = !@scheduled_meeting.active? && !mod_in_room?(@scheduled_meeting)
    @participants_count = get_participants_count(@scheduled_meeting)
    @started_ago = get_current_duration(@scheduled_meeting)
    @disclaimer = config&.external_disclaimer
  end

  def running
    respond_to do |format|
      format.json {
        render json: {
                 status: :ok,
                 running: mod_in_room?(@scheduled_meeting),
                 interval: Rails.configuration.cable_polling_secs.to_i,
                 can_join_or_create: join_or_create?
               }
      }
    end
  end

  def updateMeetingData
    respond_to do |format|
      format.json {
        render json: {
                  status: :ok,
                  running: mod_in_room?(@scheduled_meeting),
                  participants_count: get_participants_count(@scheduled_meeting),
                  start_ago: get_current_duration(@scheduled_meeting),
                  ended: !@scheduled_meeting.active? && !mod_in_room?(@scheduled_meeting),
                  can_join_or_create: join_or_create?
               }
      }
    end
  end

  def destroy
    event_id = @scheduled_meeting.brightspace_calendar_event&.event_id
    if event_id
      Rails.logger.info('Found brightspace event, sending delete calendar event')

      return_path = room_path(@room), { notice: t('default.scheduled_meeting.destroyed') }
      redirect_if_brightspace(return_path) || redirect_to(*return_path)
    else
      Rails.logger.info('Brightspace event not found')
      respond_to do |format|
        format.html { redirect_to room_path(@room), notice: t('default.scheduled_meeting.destroyed') }
        format.json { head :no_content }
      end
    end
    moodle_calendar_events_ids = {}
    moodle_calendar_events_ids = MoodleCalendarEvent.where(scheduled_meeting_hash_id: @scheduled_meeting.hash_id).pluck(:event_id)
    if @room.can_delete_moodle_calendar_event && moodle_calendar_events_ids.any?
      moodle_token = @room.consumer_config.moodle_token
      if @scheduled_meeting.recurring?
        DeleteRecurringEventsInMoodleCalendarJob.perform_later(moodle_token, moodle_calendar_events_ids, @app_launch.context_id, {nonce: @app_launch.nonce})
      else
        Moodle::API.delete_calendar_event(moodle_token, moodle_calendar_events_ids.first, @app_launch.context_id, {nonce: @app_launch.nonce})
        MoodleCalendarEvent.find_by(event_id: moodle_calendar_events_ids.first).destroy
      end
    end
    @scheduled_meeting.destroy
  end

  def guest_logout
    logout_guest
    redirect_to external_room_scheduled_meeting_path(@room, @scheduled_meeting)
  end

  private

  # Sets :repeat as nil if it's blank. We want it as nil in the database in order
  # for a non-recurring meeting to work
  def set_blank_repeat_as_nil
    if params.dig(:scheduled_meeting, :repeat)&.blank?
      params[:scheduled_meeting][:repeat] = nil
    end
  end

  def join_or_create?
    can_join = (@user.present? && !(wait_for_mod?(@scheduled_meeting, @user) &&
      !mod_in_room?(@scheduled_meeting))) || (!@user.present? && mod_in_room?(@scheduled_meeting))

    can_join
  end

  def scheduled_meeting_params(room)
    attrs = [
      :name, :recording, :duration, :description, :welcome, :repeat,
      :disable_external_link, :disable_private_chat, :disable_note, :create_moodle_calendar_event, :mark_moodle_attendance
    ]
    attrs << [:wait_moderator] if room.allow_wait_moderator
    attrs << [:all_moderators] if room.allow_all_moderators
    params.require(:scheduled_meeting).permit(*attrs)
  end

  def validate_start_at(scheduled_meeting)
    begin
      ScheduledMeeting.parse_start_at(
        params[:scheduled_meeting][:date], params[:scheduled_meeting][:time]
      ) > (DateTime.now - 5.minutes)
    rescue Date::Error
      scheduled_meeting.start_at = nil
      scheduled_meeting.errors.add(:start_at, t('default.scheduled_meeting.error.invalid_start_at'))
      false
    end
  end

  def redirect_if_brightspace(return_path)
    if @app_launch.brightspace_oauth
      Rails.logger.info('Found brightspace, sending calendar event')
      push_redirect_to_session!('brightspace_return_to', *return_path)
      case action_name
      when 'create'
        redirect_to(send_create_calendar_event_room_scheduled_meeting_path(@room, @scheduled_meeting))
      when 'update'
        redirect_to(send_update_calendar_event_room_scheduled_meeting_path(@room, @scheduled_meeting))
      when 'destroy'
        redirect_to(send_delete_calendar_event_room_scheduled_meeting_path(@room, @scheduled_meeting))
      end
      true
    else
      Rails.logger.info('Brightspace not found')
      false
    end
  end
end
