class Room < ApplicationRecord
  before_save :default_values

  has_many :scheduled_meetings
  has_many :app_launches, primary_key: :handler, foreign_key: :room_handler

  attr_accessor :can_grade

  def last_launch
    app_launches.order('created_at DESC').first
  end

  def to_param
    self.handler
  end

  def self.from_param(param)
    find_by(handler: param)
  end

  def can_create_moodle_calendar_event
    moodle_token = self.consumer_config&.moodle_token
    if moodle_token
      Moodle::API.token_functions_configured?(moodle_token, ['core_calendar_create_calendar_events'])
    else
      false
    end
  end

  def can_delete_moodle_calendar_event
    moodle_token = self.consumer_config&.moodle_token
    if moodle_token
      Moodle::API.token_functions_configured?(moodle_token, ['core_calendar_delete_calendar_events'])
    else
      false
    end
  end

  def can_mark_moodle_attendance
    moodle_token = self.consumer_config&.moodle_token
    required_functions = [
      'core_course_get_contents',
      'core_enrol_get_enrolled_users',
      'mod_attendance_add_attendance',
      'mod_attendance_add_session',
      'mod_attendance_get_session',
      'mod_attendance_update_user_status'
    ]
    if moodle_token
      Moodle::API.token_functions_configured?(moodle_token, required_functions)
    else
      false
    end
  end

  def consumer_config
    ConsumerConfig.find_by(key: self.consumer_key)
  end

  def moodle_token
    consumer_config&.moodle_token
  end

  def moodle_group_select_enabled?
    moodle_token&.group_select_enabled?
  end

  def show_all_moodle_groups?
    moodle_token&.show_all_groups
  end

  def default_values
    self.handler ||= Digest::SHA1.hexdigest(SecureRandom.uuid)
    self.moderator = random_password(8) if moderator.blank?
    self.viewer = random_password(8, moderator) if viewer.blank?
  end

  def params_for_get_recordings
    { meetingID: self.meeting_id, meetingIDWildcard: true }
  end

  alias_method :params_for_get_all_meetings, :params_for_get_recordings
  
  def meeting_id
    "#{self.handler}-#{self.id}"
  end

  def attributes_for_meeting
    {
      recording: self.recording,
      all_moderators: self.all_moderators,
      wait_moderator: self.wait_moderator
    }
  end

  def update_recurring_meetings
    self.scheduled_meetings.inactive.recurring.find_each do |meeting|
      meeting.update_to_next_recurring_date
    end
  end

  def institution_guid
    self.consumer_config&.institution_guid
  end

  private

  def random_password(length, reference = '')
    o = [('a'..'z'), ('A'..'Z'), ('0'..'9')].map(&:to_a).flatten
    password = ''
    loop do
      password = (0...length).map { o[rand(o.length)] }.join
      break unless password == reference
    end
    password
  end
end
