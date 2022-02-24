FactoryBot.define do
  factory :brightspace_calendar_event do |b|
    b.created_at                 { Time.zone.now }
    b.event_id                   { Faker::Number.number(digits: 6) }
    b.link_id                    { Faker::Number.number(digits: 6) }
    b.updated_at                 { Time.zone.now }

    b.association :scheduled_meeting_hash_id, factory: :scheduled_meeting
    b.association :room_id, factory: :room
  end
end
