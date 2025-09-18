# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

attrs = {
  key: Mconf::Env.fetch('SESSION_COOKIE_KEY', "_app_rooms_session_#{BbbAppRooms::Application::VERSION}"),
  secure: !Mconf::Env.fetch_boolean('COOKIES_SECURE_OFF', false),
  same_site: Mconf::Env.fetch('COOKIES_SAME_SITE', 'None'),
  partitioned: true
}
Rails.application.config.session_store(:cookie_store, **attrs)
