ActiveSupport.on_load(:after_initialize) do
  if Mconf::Env.fetch_boolean('SMTP_ENABLED', false)
    ActionMailer::Base.delivery_method = :smtp
    ActionMailer::Base.perform_deliveries = true
    ActionMailer::Base.raise_delivery_errors = true

    ActionMailer::Base.default_url_options = {
      protocol: Mconf::Env.fetch('URL_PROTOCOL', 'http'),
      host: Mconf::Env.fetch('URL_HOST', 'localhost')
    }

    settings = {
      address:                Mconf::Env.fetch('SMTP_SERVER'),
      port:                   Mconf::Env.fetch_int('SMTP_PORT', 1025),
      domain:                 Mconf::Env.fetch('SMTP_DOMAIN'),
      enable_starttls_auto:   Mconf::Env.fetch_boolean('SMTP_AUTO_TLS', false),
      authentication:         Mconf::Env.fetch('SMTP_AUTH_TYPE')&.to_sym,
      tls:                    Mconf::Env.fetch_boolean('SMTP_USE_TLS', false),
      user_name:              Mconf::Env.fetch('SMTP_LOGIN'),
      password:               Mconf::Env.fetch('SMTP_PASSWORD')
    }

    # remove nil/empty values
    settings.delete_if { |_k, v| v.blank? }

    ActionMailer::Base.smtp_settings = settings
  end
end
