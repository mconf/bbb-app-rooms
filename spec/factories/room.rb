FactoryBot.define do
  factory :room do |r|
    r.all_moderators         { Faker::Boolean.boolean }
    r.allow_wait_moderator   { Faker::Boolean.boolean }
    r.allow_all_moderators   { Faker::Boolean.boolean }
    r.created_at             { Time.zone.now }
    r.description            { Faker::Lorem.sentence }
    r.handler                { 'handler' }
    r.moderator              { Faker::Name.unique.name }
    r.name                   { Faker::Educator.course_name }
    r.recording              { Faker::Boolean.boolean }
    r.updated_at             { Time.zone.now }
    r.viewer                 { Faker::Name.unique.name }
    r.wait_moderator         { Faker::Boolean.boolean }
    r.welcome                { Faker::Lorem.sentence }
    
    association :consumer_key, factory: :consumer_config
  end
end
