module MeetingsHelper
  def self.bucket_configured?
    !Rails.configuration.meetings_bucket_key_id.blank? &&
      !Rails.configuration.meetings_bucket_secret.blank? &&
      !Rails.configuration.meetings_bucket_name.blank?
  end

  def self.has_required_info_for_bucket?(meeting)
    !meeting[:meetingID].blank? &&
      !meeting[:internalMeetingID].blank? &&
      !ApplicationHelper.get_shared_secret_guid(meeting[:room]).blank?
  end

  def self.file_exists_on_bucket?(meeting, room, file_type)
    meeting[:room] = room
    if self.bucket_configured? && self.has_required_info_for_bucket?(meeting)
      file = self.filename_for_datafile(file_type)
      return false if file.nil?

      key = Mconf::BucketApi.gen_key(meeting, file)
      Mconf::BucketApi.file_exists?(meeting, key)
    else
      false
    end
  end

  def self.filename_for_datafile(type)
    case type
    when :participants
      Rails.configuration.meeting_participants_filename
    when :notes
      Rails.configuration.meeting_notes_filename
    when :dashboard
      Rails.configuration.meeting_learning_dashboard_filename
    else
      nil
    end
  end

  def filter_meetings_by_group_id(meetings_array, group_id)
    filtered_meetings = meetings_array.select do |meeting|
      metadata = meeting.dig(:meeting, :metadata)
      metadata && metadata[:"bbb-moodle-group-id"]&.to_i == group_id.to_i
    end

    filtered_meetings
  end

  def filter_meetings_without_group_id(meetings_array)
    filtered_meetings = meetings_array.select do |meeting|
      metadata = meeting.dig(:meeting, :metadata)
      metadata && metadata[:"bbb-moodle-group-id"].nil?
    end

    filtered_meetings
  end
end
