Rails.application.config.after_initialize do
  config = Rails.application.config
  next unless config.maintenance_enabled
  next if Mconf::Maintenance.valid_window?

  Rails.logger.error(
    '[Maintenance] MCONF_MAINTENANCE_ENABLED is true but the window is invalid, so it is disabled. ' \
    'Expected ISO datetimes in Brasilia time with the end after the start (e.g. 2026-11-15T08:00), ' \
    "got start=#{config.maintenance_start.inspect} end=#{config.maintenance_end.inspect}"
  )
end
