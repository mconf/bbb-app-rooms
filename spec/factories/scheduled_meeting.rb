FactoryBot.define do
  factory :scheduled_meeting do |s|
    s.room_id                 { 1 }
    s.name                    { Faker::Educator.course_name }
    s.start_at                { Time.zone.now }
    s.duration                { 60 }
    s.recording               { Faker::Boolean.boolean }
    s.wait_moderator          { Faker::Boolean.boolean }
    s.all_moderators          { Faker::Boolean.boolean }
    s.created_at              { Time.zone.now }
    s.updated_at              { Time.zone.now }
    s.description             { Faker::Lorem.sentence }
    s.welcome                 { Faker::Lorem.sentence }
    s.created_by_launch_nonce { 'handler' }
    s.repeat                  { 'every_two_weeks' }
    s.disable_external_link   { Faker::Boolean.boolean }
    s.disable_private_chat    { Faker::Boolean.boolean }
    s.disable_note            { Faker::Boolean.boolean }
    s.hash_id                 { Faker::Number.number(digits: 20) }
  end
end
