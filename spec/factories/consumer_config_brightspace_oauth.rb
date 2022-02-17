FactoryBot.define do
  factory :consumer_config_brightspace_oauth do |bo|
    bo.url            { Faker::Lorem.paragraph }
    bo.client_id      { Faker::Lorem.paragraph }
    bo.client_secret  { Faker::Lorem.paragraph }
    bo.scope          { Faker::Lorem.paragraph }

  end
end
