FactoryBot.define do
  factory :app_launch do |a|
      a.created_at    { Time.now }
      a.expires_at    { Time.now + 1.day }
      a.params        { Faker::Lorem.characters(number: 20) }
      a.nonce         { Faker::Lorem.characters(number: 20) }
      a.omniauth_auth { Faker::Omniauth.google }
      a.room_handler  { Faker::Lorem.characters(number: 20) }
      a.updated_at    { Time.now }
  end
end
