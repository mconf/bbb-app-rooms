class ScheduledMeeting < ApplicationRecord
  paginates_per 10

  REPEAT_OPTIONS = {
    weekly: 1.week,
    every_two_weeks: 2.weeks
  }.stringify_keys.freeze

  belongs_to :room

  validates :room, presence: true
  validates :name, presence: true
  validates :start_at, presence: true
  validates :duration, presence: true
  validates :repeat, inclusion: { in: [nil] + ScheduledMeeting::REPEAT_OPTIONS.keys }

  after_initialize :init

  scope :active, -> (reverse = false) {
    # TODO: temporary, disable the timezone via cookie until it's 100%
    tolerance = Rails.application.config.force_default_timezone ? 1.hour : 0.seconds

    attrs = ["start_at + (interval '1 seconds' * duration) >= ?", DateTime.now.utc - tolerance]
    if reverse
      where.not(*attrs)
    else
      where(*attrs)
    end
  }

  scope :inactive, -> {
    active(true)
  }

  scope :recurring, -> {
    where.not(repeat: nil)
  }

  def self.from_param(param)
    find_by(id: param)
  end

  def to_param
    self.id.to_s
  end

  def self.durations_for_select(locale)
    {
      '5m': 5 * 60,
      '10m': 10 * 60,
      '15m': 15 * 60,
      '20m': 20 * 60,
      '30m': 30 * 60,
      '45m': 45 * 60,
      '1h': 60 * 60,
      '2h': 2 * 60 * 60,
      '3h': 3 * 60 * 60,
      '4h': 4 * 60 * 60,
      '5h': 5 * 60 * 60,
      '6h': 6 * 60 * 60,
      '8h': 8 * 60 * 60,
      '12h': 12 * 60 * 60,
      '24h': 24 * 60 * 60,
    }.map { |k, v|
      [I18n.t("default.scheduled_meeting.durations.#{k}", locale: locale), v]
    }
  end

  def self.repeat_options_for_select(locale)
    ([nil] + ScheduledMeeting::REPEAT_OPTIONS.keys).map do |k|
      [I18n.t("default.scheduled_meeting.repeat_options.#{k || 'none'}", locale: locale), k]
    end
  end

  def self.parse_start_at(date, time, locale = I18n.locale, zone = Time.zone)
    format_date = I18n.t('default.formats.flatpickr.date_ruby', locale: locale)
    format_time = I18n.t('default.formats.flatpickr.time_ruby', locale: locale)

    zone = ActiveSupport::TimeZone[zone] if zone.is_a?(String)
    zone_str = Time.at(zone.utc_offset.abs).utc.strftime(format_time)
    zone_sig = zone.utc_offset < 0 ? '-' : '+'

    # format string example: "%Y-%m-%dT%H:%M%z"
    DateTime.strptime(
      "#{date}T#{time}#{zone_sig}#{zone_str}", "#{format_date}T#{format_time}%z"
    )
  end

  def active?
    # TODO: temporary, disable the timezone via cookie until it's 100%
    tolerance = Rails.application.config.force_default_timezone ? 1.hour : 0.seconds

    start_at + duration.seconds >= DateTime.now.utc - tolerance
  end

  def meeting_id
    "#{room.meeting_id}-#{self.id}"
  end

  def create_options(user)
    # standard API params
    opts = {
      moderatorPW: self.room.moderator,
      attendeePW: self.room.viewer,
      welcome: self.welcome,
      record: self.recording,
    }

    # set the duration + 1h if configured to do so in the consumer
    config = ConsumerConfig.select(:set_duration).find_by(key: self.room.consumer_key)
    opts[:duration] = duration_minutes + 60 if !config.blank? && config.set_duration

    # will be added as meta_bbb-*
    meta_bbb = {
      origin: 'LTI',
      'recording-name': self.name,
      'recording-description': self.description,
      'room-handler': self.room.handler,
      'meeting-db-id': self.id,
    }

    # extra launch params, if we can found them
    launch_params = AppLaunch.find_by(nonce: user.launch_nonce)
    if launch_params.present?
      meta_bbb.merge!(
        {
          'origin-server-name': launch_params.params['tool_consumer_info_product_family_code'],
          'origin-server-url': launch_params.consumer_domain,
          'origin-version': launch_params.params['tool_consumer_info_version'],
          'origin-lti-version': launch_params.params['lti_version'],
          'context-id': launch_params.params['context_id'],
          'context-title': launch_params.params['context_title'],
          'context-label': launch_params.params['context_label'],
          'context-type': launch_params.params['context_type'],
          'resource_link_title': launch_params.params['resource_link_title'],
          'resource_link_id': launch_params.params['lis_course_section_sourcedid'],
          'course-section-sourcedid': launch_params.params['context_type'],
          'launch-nonce': launch_params.nonce,
          'oauth-consumer-key': launch_params.oauth_consumer_key,
        }
      )
    end

    meta_bbb.each { |k, v| opts["meta_bbb-#{k}"]= v }

    opts
  end

  def start_at_date(locale)
    format = I18n.t('default.formats.flatpickr.date_ruby', locale: locale)
    self.start_at.strftime(format) if self.start_at
  end

  def start_at_time(locale)
    format = I18n.t('default.formats.flatpickr.time_ruby', locale: locale)
    self.start_at.strftime(format) if self.start_at
  end

  def broadcast_conference_started
    ActionCable.server.broadcast(
      WaitChannel.full_channel_name({ room: self.room.to_param, meeting: self.to_param }),
      action: 'started'
    )
  end

  # Example of params:
  #   "date"=>"2020-06-12", "time"=>"17:15"
  def set_dates_from_params(params, locale = I18n.locale, zone = Time.zone)
    self.start_at = ScheduledMeeting.parse_start_at(params[:date], params[:time], locale, zone)
  end

  # If the users of this room are allowed to change `all_moderators`, returns the value
  # set in this scheduled meeting. Otherwise returns the default value.
  def check_all_moderators
    if self.room.allow_all_moderators
      self.all_moderators
    else
      ScheduledMeeting.new.all_moderators
    end
  end

  # If the users of this room are allowed to change `wait_moderator`, returns the value
  # set in this scheduled meeting. Otherwise returns the default value.
  def check_wait_moderator
    if self.room.allow_wait_moderator
      self.wait_moderator
    else
      ScheduledMeeting.new.wait_moderator
    end
  end

  def duration_minutes
    self.duration / 60
  end

  # Update this scheduled meeting to the date it should be in its next iteration.
  # If this is not a recurring meeting or if this meeting is still active won't do anything.
  def update_to_next_recurring_date
    return if self.repeat.blank? || self.active?

    self.start_at += ScheduledMeeting::REPEAT_OPTIONS[self.repeat] while !self.active?
    self.save
  end

  private

  def init
    self.duration ||= 60 * 60 # 1h
    self.start_at ||= (DateTime.now.utc + 1.hour).beginning_of_hour
  end
end
