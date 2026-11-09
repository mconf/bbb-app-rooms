module MaintenanceHelper
  def maintenance_active?
    Mconf::Maintenance.active?
  end

  def maintenance_window_in_time_zone
    [Mconf::Maintenance.starts_at.in_time_zone(Time.zone), Mconf::Maintenance.ends_at.in_time_zone(Time.zone)]
  end

  # Window boundaries for the scheduling form JS, plus the repeat periods in days
  def maintenance_window_data_attrs
    starts_at, ends_at = maintenance_window_in_time_zone
    {
      starts_at: starts_at.strftime('%Y-%m-%dT%H:%M'),
      ends_at: ends_at.strftime('%Y-%m-%dT%H:%M'),
      repeat_days: ScheduledMeeting::REPEAT_OPTIONS.transform_values { |period| period.in_days.to_i },
    }
  end

  # kind: :single or :recurring, see ScheduledMeeting.maintenance_overlap
  def maintenance_conflict_message(kind)
    t("maintenance_conflict.#{kind}", period: maintenance_window_period(:short))
  end

  # style: :long (banner) or :short (scheduling alert)
  def maintenance_window_period(style)
    starts_at, ends_at = maintenance_window_in_time_zone
    date = ->(time) { I18n.l(time, format: t('maintenance_window.date_format')) }
    hour = lambda do |time|
      format_key = time.min.zero? ? 'hour_format' : 'hour_minute_format'
      I18n.l(time, format: t("maintenance_window.#{format_key}"))
    end
    variant = starts_at.to_date == ends_at.to_date ? 'same_day' : 'multi_day'

    t("maintenance_window.#{style}.#{variant}",
      start_date: date.call(starts_at), end_date: date.call(ends_at),
      start_at: hour.call(starts_at), end_at: hour.call(ends_at))
  end
end
