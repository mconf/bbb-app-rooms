module MeetingsHelper
  def self.bucket_configured?
    !Rails.configuration.meetings_bucket_key_id.blank? &&
      !Rails.configuration.meetings_bucket_secret.blank? &&
      !Rails.configuration.meetings_bucket_name.blank?
  end

  def self.has_required_info_for_bucket?(meeting)
    !meeting.meetingid.blank? &&
      !meeting.internal_meeting_id.blank? &&
      !meeting&.room&.owner&.institution&.shared_secret_guid.blank?
  end

  def self.file_exists_on_bucket?(meeting, file_type)
    if self.bucket_configured? && self.has_required_info_for_bucket?(meeting)
      file = self.filename_for_datafile(file_type)
      return false if file.nil?

      key = Mconf::BucketApi.gen_key(meeting, file)
      Mconf::BucketApi.file_exists?(meeting, key)
    else
      false
    end
  end

  def filename_for_datafile(type)
    case type
    when :participants
      Rails.configuration.meeting_participants_filename
    when :notes
      Rails.configuration.meeting_notes_filename
    else
      nil
    end
  end
end
