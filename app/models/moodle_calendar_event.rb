class MoodleCalendarEvent < ApplicationRecord
  validates :scheduled_meeting_hash_id, presence: true
  validates :event_id, presence: true
end
  