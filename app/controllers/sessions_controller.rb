# frozen_string_literal: true

require 'bbb_api'

class SessionsController < ApplicationController
  include ApplicationHelper
  include BbbApi

  before_action :find_room, only: %i[create_session_token]
  before_action :validate_room, only: %i[create_session_token]
  before_action :find_app_launch, only: %i[create_session_token]

  def new; end

  def create
    omniauth_auth = request.env['omniauth.auth']
    Rails.logger.info "Omniauth authentication information auth=#{omniauth_auth.inspect} " # \

    # Return error if authentication fails
    unless omniauth_auth&.uid
      Rails.logger.info "Authentication failed, redirecting to #{omniauth_retry_path(params)}"
      redirect_to(omniauth_retry_path(params)) && return
    end
    # As authentication did not fail, initialize the session

    provider = params['provider']
    session['omniauth_auth'] ||= {}
    session['omniauth_auth'][provider] = omniauth_auth

    omniauth_params = request.env['omniauth.params']
    if provider == 'brightspace'
      room_param = omniauth_params['room_id']
      scheduled_meeting_param = omniauth_params['id']
      case omniauth_params['event']
      when 'send_create_calendar_event'
        redirect_to send_create_calendar_event_room_scheduled_meeting_path(room_param, scheduled_meeting_param)
      when 'send_update_calendar_event'
        redirect_to send_update_calendar_event_room_scheduled_meeting_path(room_param, scheduled_meeting_param)
      when 'send_delete_calendar_event'
        redirect_to send_delete_calendar_event_room_scheduled_meeting_path(room_param, scheduled_meeting_param)
      end
    elsif provider == 'bbbltibroker'
      redirect_to(
        room_launch_url(
          launch_nonce: params['launch_nonce'], provider: provider, session_set: true
        )
      )
    end
  end

  # Generates a single-use token to retrieve the user session (`app_launch`) in external contexts
  # (e.g., joining a meeting in a new tab) where the original cookie can no longer be accessed.
  # Responds with JSON
  def create_session_token
    # exit with error if app_launch is not present
    if @app_launch.blank?
      Rails.logger.info "The session is not valid, returning a 403"
      set_error('room', 'forbidden', :forbidden)
      respond_with_error(@error)
      return
    end

    nonce = SecureRandom.hex(16)
    Rails.cache.write("session_token/#{nonce}", @app_launch.nonce, expires_in: 2.minutes)

    render json: { token: nonce }
  end

  def failure
    # TODO: there are different types of errors, not all require a retry
    provider = request.env['omniauth.strategy'].name.to_sym
    redirect_to(omniauth_retry_path(provider: provider, launch_nonce: params['launch_nonce']))
  end

  def retry
    @launch_nonce = params['launch_nonce']
  end
end
