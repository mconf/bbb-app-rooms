# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

attrs = {
  key: '_app_rooms_session',
  secure: !Mconf::Env.fetch_boolean('COOKIES_SECURE_OFF', false),
  same_site: Mconf::Env.fetch('COOKIES_SAME_SITE', 'None'),
  partitioned: true
}
Rails.application.config.session_store(:cookie_store, **attrs)
