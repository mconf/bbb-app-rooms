
class CocController < ApplicationController
  include ApplicationHelper

  before_action -> {authenticate_with_oauth!(:bbbltibroker)},
    only: :launch, raise: false
  before_action :set_launch_room, only: %i[launch]
  before_action :find_app_launch, only: %i[launch classes]

  # GET /launch
  def launch
    redirect_to(coc_classes_path(@app_launch.room_handler))
  end

  def classes
    @schools = @app_launch.coc_class_params[:schools]
  end

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

    bbbltibroker_url = omniauth_bbbltibroker_url("/api/v1/sessions/#{launch_nonce}/invalidate")
    Rails.logger.info "Making a session request to #{bbbltibroker_url}"
    session_params = JSON.parse(
      RestClient.get(
        bbbltibroker_url,
        'Authorization' => "Bearer #{omniauth_client_token(omniauth_bbbltibroker_url)}"
      )
    )

    AppLaunch::remove_old_app_launches if Rails.application.config.launch_remove_old_on_launch

    # Store the data from this launch for easier access
    expires_at = Rails.configuration.launch_duration_mins.from_now
    app_launch = AppLaunch.find_or_create_by(nonce: launch_nonce) do |launch|
      launch.update(
        params: launch_params,
        omniauth_auth: session['omniauth_auth']['bbbltibroker'],
        expires_at: expires_at
      )
    end

    # Use this data only during the launch
    # From now on, take it from the AppLaunch
    session.delete('omniauth_auth')
  end

  def find_app_launch
    if permitted_params.key? 'launch_nonce'
      @app_launch = AppLaunch.find_by(nonce: permitted_params['launch_nonce'])
    elsif permitted_params.key? 'handler'
      @app_launch = AppLaunch.where(room_handler: permitted_params['handler']).last
    end
  end

  def permitted_params
    params.permit('launch_nonce', 'handler')
  end
end
