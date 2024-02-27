class EduplayUpload < ApplicationRecord
  validates :recording_id, presence: true

  def self.recording_uploads(recording_id)
    where(recording_id: recording_id)
  end
end