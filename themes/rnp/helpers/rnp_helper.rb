module RnpHelper

  def format_date(date, format=:short_custom, include_time=true)
    if date.present?
      if date.is_a?(Integer) && date.to_s.length == 13
        value = Time.zone.at(date/1000)
      else
        value = Time.zone.at(date)
      end
      if include_time
        I18n.l(value, format: format)
      else
        I18n.l(value.to_date, format: format)
      end
    else
      nil
    end
  end

  def format_time(date)
    if date.present?
      if date.is_a?(Integer) && date.to_s.length == 13
        value = Time.zone.at(date/1000)
      else
        value = Time.zone.at(date)
      end
      value.to_s(:time)
    else
      nil
    end
  end

  def recording_duration_secs(recording)
    playbacks = recording[:playbacks]
    valid_playbacks = playbacks.reject { |p| p[:type] == 'statistics' }
    return 0 if valid_playbacks.empty?

    len = valid_playbacks.first[:length]
    return 0 if len.nil?

    len * 60
  end

  def duration_in_hours_and_minutes(duration, short=false)
    distance_of_time_in_hours_and_minutes(0, duration, short)
  end

  def distance_of_time_in_hours_and_minutes(from_time, to_time, short)
    from_time = from_time.to_time if from_time.respond_to?(:to_time)
    to_time = to_time.to_time if to_time.respond_to?(:to_time)
    distance_in_hours   = (((to_time - from_time).abs) / 3600).floor
    distance_in_minutes = ((((to_time - from_time).abs) % 3600) / 60).round

    words = ''

    if distance_in_hours > 0
      words << I18n.t("helpers.distance_of_time_in_hours_and_minutes.#{short ? 'short' : 'long'}.hour", count: distance_in_hours)
      if distance_in_minutes > 0
        words << (short ? '' : " #{I18n.t('helpers.distance_of_time_in_hours_and_minutes.long.connector')} ")
      end
    end

    if distance_in_minutes > 0
      words << I18n.t("helpers.distance_of_time_in_hours_and_minutes.#{short ? 'short' : 'long'}.minute", count: distance_in_minutes)
    end

    words
  end

  def current_formatted_time_zone
    ActiveSupport::TimeZone[Time.zone.name].to_s.gsub(/[^\s]*\//, '').gsub(/_/, ' ')
  end

  def get_custom_duration(duration)
    duration_in_time = ScheduledMeeting.convert_duration_to_time(duration)
    return time = duration_in_time[0].to_s + ':' + duration_in_time[1].to_s
  end

  def playback_url(room, record_id, playback)
    if Rails.application.config.playback_url_authentication
      recording_playback_url(room, record_id, playback[:type])
    else
      playback[:url]
    end
  end

  def ext_rnp_link(page)
    link = links_external(page, I18n.locale)
    link.nil? ? links_external(page, :en) : link
  end

  def links_external(page, locale)
    links = {
      # TODO ADD LINKS
      terms: {
        'en': 'https://ajuda.rnp.br/conferenciaweb/termo-de-uso',
        'pt': 'https://ajuda.rnp.br/conferenciaweb/termo-de-uso',
      }
    }
    return links[page][locale]
  end

  def recurring_meeting?(meeting_id)
    meeting = ScheduledMeeting.find_by(id: meeting_id)

    meeting.present? && meeting[:repeat].present?
  end

  def meeting_recurrence(meeting_id)
    ScheduledMeeting.find_by(id: meeting_id)[:repeat]
  end
end