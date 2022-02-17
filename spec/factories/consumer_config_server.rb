FactoryBot.define do
  factory :consumer_config_server do |cs|
    cs.endpoint           { Faker::Movie.quote }
    cs.internal_endpoint  { Faker::Movie.quote }
    cs.secret             { Faker::Movie.quote }

    cs.association :consumer_config_id, factory: :consumer_config
  end
end
