# frozen_string_literal: true

require 'bigbluebutton_api'

class ApplicationController < ActionController::Base
  before_action :set_current_locale
  before_action :allow_iframe_requests

  # the scope and how many rooms we keep in the session
  # keeping too many might result in a cookie overflow
  COOKIE_ROOMS_SCOPE = 'rooms'
  COOKIE_ROOMS_MAX_KEYS = 3

  unless Rails.application.config.consider_all_requests_local
    rescue_from StandardError do |e|
      on_500(e)
    end
    rescue_from ActionController::RoutingError, with: :on_404
    rescue_from ActiveRecord::RecordNotFound, with: :on_404
    rescue_from ActionController::UnknownFormat, with: :on_406
  end

    rescue_from BigBlueButton::BigBlueButtonException do |e|
      Rails.logger.error "Exception caught: error=#{e.key} " \
                         "class=#{e.class.name} message='#{e.message}'"

      if e.key.to_s == 'meetingAlreadyBeingCreated' && @room.present? && @scheduled_meeting.present?
        add_to_room_session(@room, 'auto_join', 'true')
        redirect_to wait_room_scheduled_meeting_path(@room, @scheduled_meeting)
      else
        redirect_back(fallback_location: room_path(@room),
                      notice: t('default.app.bigbluebutton_error', status: e.key))
      end
    end

  # Check if the user authentication exists in the session and is valid (didn't expire).
  # On launch, go get the credentials needed.
  def authenticate_user!
    unless omniauth_provider?(:bbbltibroker)
      Rails.logger.info "Provider is not bbbltibroker"
      return true
    end

    # Assume user authenticated if session[:omaniauth_auth] is set
    if session['omniauth_auth'] &&
       Time.now.to_time.to_i < session['omniauth_auth']["credentials"]["expires_at"].to_i
      Rails.logger.info "Found a valid omniauth_auth in the session, user already authenticated"
      return true
    end

    # If we got here even after the session was set and we couldn't find it, the browser
    # is probably blocking cookies, so abort and got to the retry page
    if params[:session_set]
      Rails.logger.info "Session should be set but found no user, going to the retry page"
      return redirect_to(
        omniauth_retry_path(provider: 'bbbltibroker', launch_nonce: params['launch_nonce'])
      )
    end

    redirector = omniauth_authorize_path(:bbbltibroker, launch_nonce: params[:launch_nonce])
    Rails.logger.info "Redirecting to the authorization route #{redirector}"
    redirect_to(redirector) and return true
  end

  # Find the user info in the session.
  # It's stored scoped by the room the user is accessing.
  def find_user
    room_session = get_room_session(@room)
    if room_session.present?
      user_params = AppLaunch.find_by(nonce: room_session['launch']).user_params
      @user = BbbAppRooms::User.new(user_params)
      Rails.logger.info "Found the user #{@user.email} (#{@user.uid}, #{@user.launch_nonce})"

      # update the locale so we use the user's locale, if any
      set_current_locale
    end

    # TODO: check expiration here?
    # return true if session['omniauth_auth'] &&
    #                Time.now.to_time.to_i < session['omniauth_auth']["credentials"]["expires_at"].to_i

  end

  def authorize_user!(action, resource)
    redirect_to errors_path(401) unless Abilities.can?(@user, action, resource)
  end

  def find_room
    @room = if params.key?(:room_id)
              Room.from_param(params[:room_id])
            else
              Room.from_param(params[:id])
            end

    # Exit with error if room was not found
    if @room.blank?
      Rails.logger.info "Couldn't find a room in the URL, returning 404"
      set_error('room', 'not_found', :not_found)
      respond_with_error(@error)
      return false
    end
  end

  def validate_room
    # Exit with error by re-setting the room to nil if the session for the room.handler is not set
    room_session = get_room_session(@room)
    if room_session.blank?
      Rails.logger.info "The session set for this room was not found or expired: #{@room.handler}"
      remove_room_session(@room)
      set_error('room', 'forbidden', :forbidden)
      respond_with_error(@error)
      return false
    end
  end

  def set_error(model, error, status)
    @user = nil
    instance_variable_set("@#{model}".to_sym, nil)
    @error = {
      key: t("error.#{model}.#{error}.code"),
      message: t("error.#{model}.#{error}.message"),
      suggestion: t("error.#{model}.#{error}.suggestion"),
      code: t("error.#{model}.#{error}.status_code"),
      status: status
    }
  end

  def respond_with_error(error)
    respond_to do |format|
      format.html { render 'shared/error', status: error[:status] }
      format.json { render json: { error: error[:message] }, status: error[:status] }
    end
  end

  # The payload is used by lograge. We add more information to it here so that it is saved
  # in the log.
  def append_info_to_payload(payload)
    super

    payload[:session] = session['rooms'] unless session.nil?
    payload[:user] = @user unless @user.blank?
    unless @room.blank?
      payload[:room] = @room.to_param
      payload[:room_session] = get_room_session(@room)
    end
  end

  def on_error
    render_error(request.path[1..-1])
  end

  def on_404
    render_error(404)
  end

  # 406 Not Acceptable
  def on_406
    render_error(406)
  end

  def on_500(exception = nil)
    Rails.logger.error "Exception caught: class=#{exception.class.name} " \
                       "message='#{exception.message}'"
    render_error(500)
  end

  private

  def render_error(status)
    model = 'generic'
    @error = {
      key: t("error.#{model}.#{status}.code"),
      message: t("error.#{model}.#{status}.message"),
      suggestion: t("error.#{model}.#{status}.suggestion"),
      code: status,
      status: status
    }

    respond_to do |format|
      format.html { render 'shared/error', status: status }
      format.json { render json: { error: @error[:message] }, status: status }
      format.all  { render 'shared/error', status: status, content_type: 'text/html' }
    end
  end

  def set_current_locale
    locale = nil

    # try to get the locale from the LTI launch, otherwise use the browser's
    if @user.present? && !@user.locale.blank?
      locale = @user.locale
    else
      locale = browser.accept_language.first.try(:code)
    end

    case locale
    when /^pt/i
      I18n.locale = 'pt'
    else
      I18n.locale = 'en' # fallback
    end
    response.set_header("Content-Language", I18n.locale)
  end

  def allow_iframe_requests
    response.headers.delete('X-Frame-Options')
  end

  def get_room_session(room)
    session[COOKIE_ROOMS_SCOPE] ||= {}
    if room.present? && session[COOKIE_ROOMS_SCOPE].key?(room.handler)
      session[COOKIE_ROOMS_SCOPE][room.handler]
    end
  end

  def set_room_session(room, data)
    session[COOKIE_ROOMS_SCOPE] ||= {}

    # so we know which ones are the oldest ones
    data['ts'] = DateTime.now.to_i

    cleanup_room_session unless session[COOKIE_ROOMS_SCOPE].key?(room.handler)

    # they will be strings in future calls, so make them strings already
    session[COOKIE_ROOMS_SCOPE][room.handler] = data.stringify_keys
  end

  def remove_room_session(room)
    if room.present? && session.dig(COOKIE_ROOMS_SCOPE, room.handler)
      session[COOKIE_ROOMS_SCOPE].delete(room.handler)
    end
  end

  def add_to_room_session(room, key, value)
    if session.dig(COOKIE_ROOMS_SCOPE, room.handler)
      session[COOKIE_ROOMS_SCOPE][key] = value
    end
  end

  def get_from_room_session(room, key)
    if session.dig(COOKIE_ROOMS_SCOPE, room.handler)
      session[COOKIE_ROOMS_SCOPE][key]
    end
  end

  def remove_from_room_session(room, key)
    if session.dig(COOKIE_ROOMS_SCOPE, room.handler, key)
      session[COOKIE_ROOMS_SCOPE][room.handler].delete(key)
    end
  end

  # Cleanup old keys from the session to make room for a new one
  def cleanup_room_session
    keys = session[COOKIE_ROOMS_SCOPE].keys
    if keys.count > COOKIE_ROOMS_MAX_KEYS - 1
      sorted = keys.sort_by do |k|
        session[COOKIE_ROOMS_SCOPE][k]['ts']&.to_i || 0
      end
      sorted.first(keys.count - COOKIE_ROOMS_MAX_KEYS + 1).each do |k|
        session[COOKIE_ROOMS_SCOPE].delete(k)
      end
    end
  end

  # TODO: temporary, disable the timezone via cookie until it's 100%
  # Overrides https://github.com/mconf/browser-timezone-rails/blob/master/lib/browser-timezone-rails.rb#L29
  def browser_timezone
    if Rails.application.config.force_default_timezone
      Rails.application.config.default_timezone
    else
      cookies['browser.timezone']
    end
  end
end
