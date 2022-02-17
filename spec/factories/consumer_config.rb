FactoryBot.define do
  factory :consumer_config do |c|
    c.created_at                    { Time.now }
    c.download_presentation_video   { Faker::Boolean.boolean }
    c.external_disclaimer           { Faker::Lorem.paragraph }
    c.key                           { Faker::Company.suffix }
    c.message_reference_terms_use   { Faker::Boolean.boolean }
    c.set_duration                  { Faker::Boolean.boolean }
    c.updated_at                    { Time.now }
  end
end
