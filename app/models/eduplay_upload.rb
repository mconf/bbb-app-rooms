class EduplayUpload < ApplicationRecord
  validates :recording_id, presence: true

  def self.recording_uploads(recording_id)
    where(recording_id: recording_id)
  end

  # Delete all eduplay tokens that are older than 2 minutes
  def self.delete_old_tokens
    where('created_at < ?', 2.minutes.ago).destroy_all
  end
end
