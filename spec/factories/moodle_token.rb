FactoryBot.define do
  factory :moodle_token do |m|
    m.token                          { Faker::Lorem.characters(number: 32) }
    m.url                            { 'https://moodle.example.com/webservice/rest/server.php' }
    m.group_select_enabled           { false }
    m.show_all_groups                { true }
    m.presence_percentage_enabled            { false }
    m.presence_threshold_percentage          { 75 }
    m.partial_presence_threshold_percentage  { 10 }
    m.created_at                     { Time.zone.now }
    m.updated_at                     { Time.zone.now }

    association :consumer_config
  end
end
