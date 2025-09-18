# frozen_string_literal: true

OmniAuth.config.logger = Rails.logger

missing_configs = {}
missing_configs[:bbbltibroker] =
  Rails.configuration.omniauth_site[:bbbltibroker].blank? ||
  Rails.configuration.omniauth_key[:bbbltibroker].blank? ||
  Rails.configuration.omniauth_secret[:bbbltibroker].blank?

OmniAuth.config.path_prefix = "#{Rails.configuration.relative_url_root}/auth"
# As of version 2.0 of OmniAuth, it defaults to accept only POST as the request_phase method.
# Anyways, we set it here explicitly to remind that GET is a no-no
OmniAuth.config.allowed_request_methods = [:post]

module OmniAuth
  module Strategies
    class Bbbltibroker < OmniAuth::Strategies::OAuth2
      def callback_url
        # keep the launch nonce because we need it in case of errors
        full_host + script_name + callback_path +
          "?launch_nonce=#{request.params['launch_nonce']}"
      end
    end
  end
end

OmniAuth.config.on_failure = Proc.new do |env|
  case env['omniauth.strategy']&.name&.to_sym
  when :bbbltibroker
    SessionsController.action(:failure).call(env)
  end
end
# OmniAuth.config.failure_raise_out_environments = []

# This will be called before every request_phase and callback_phase
brightspace_setup_phase = lambda do |env|
  req = Rack::Request.new(env)
  session = env['rack.session']

  room_handler = req.GET&.[]('room_id') ||
                 session&.[]('omniauth.params')&.[]('room_id')

  # FIXME. This is the get_room_session in ApplicationController, but
  # we can't access that method here
  room = Room.find_by(handler: room_handler)
  room_session = session&.[](ApplicationController::COOKIE_ROOMS_SCOPE) || {}
  room_session_handler = room_session[room.handler] if room.present? &&
                                                       room_session.key?(room.handler)

  # FIXME. This is the find_app_launch in ApplicationController, but
  # we can't access that method here
  app = AppLaunch.find_by(nonce: room_session_handler['launch']) if room_session_handler.present?
  brightspace_oauth = app&.brightspace_oauth

  if app.blank? || brightspace_oauth.blank?
    # FIXME. We should use url_helpers like so:
    #   routes = redirect_path_on_failure = Rails.application.routes.url_helpers
    #   redirect_path_on_failure = routes.room_url(room_handler)
    # But it returns /rooms/rooms/:id, instead of /rooms/:id
    redirect_path_on_failure = "/rooms/#{room_handler}/error/oauth_error"
    env['omniauth.strategy'].options[:redirect_path_on_failure] = redirect_path_on_failure
    env['omniauth.strategy'].fail!(:setup_failure)
    return
  end

  env['omniauth.strategy'].options[:client_id] = brightspace_oauth.client_id
  env['omniauth.strategy'].options[:client_secret] = brightspace_oauth.client_secret
  env['omniauth.strategy'].options[:scope] = brightspace_oauth.scope
  env['omniauth.strategy'].options[:client_options].site = brightspace_oauth.url
end

Rails.application.config.middleware.use(OmniAuth::Builder) do
  # provider :developer unless Rails.env.production?
  # Initialize the provider
  unless missing_configs[:bbbltibroker]
    provider(
      :bbbltibroker,
      Rails.configuration.omniauth_key[:bbbltibroker],
      Rails.configuration.omniauth_secret[:bbbltibroker],
      provider_ignores_state: true,
      path_prefix: "#{Rails.configuration.relative_url_root}/auth",
      omniauth_root: Rails.configuration.omniauth_root[:bbbltibroker].to_s,
      raw_info_url: "#{Rails.configuration.omniauth_root[:bbbltibroker]}/api/v1/user.json",
      scope: 'api',
      info_params: %w[
        full_name
        first_name
        last_name
        email
      ],
      client_options: {
        site: Rails.configuration.omniauth_site[:bbbltibroker].to_s,
        code: 'rooms',
        authorize_url: "#{Rails.configuration.omniauth_root[:bbbltibroker]}/oauth/authorize",
        token_url: "#{Rails.configuration.omniauth_root[:bbbltibroker]}/oauth/token",
        revoke_url: "#{Rails.configuration.omniauth_root[:bbbltibroker]}/oauth/revoke",
      }
    )
  end

  provider :brightspace, setup: brightspace_setup_phase
end
