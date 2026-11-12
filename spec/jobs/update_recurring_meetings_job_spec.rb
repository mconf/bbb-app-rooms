require 'rails_helper'

RSpec.describe UpdateRecurringMeetingsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:url) { 'https://moodle.example.com/webservice/rest/server.php' }
  let(:consumer_config) { FactoryBot.create(:consumer_config) }
  let!(:moodle_token) { FactoryBot.create(:moodle_token, consumer_config: consumer_config, url: url) }
  let(:room) { FactoryBot.create(:room, consumer_key: consumer_config.key) }
  let(:app_launch) { FactoryBot.create(:app_launch, params: { 'context_id' => '30' }) }

  # A biweekly meeting at 19:06 in Moscow (16:06 UTC) whose last occurrence
  # already ended, so the job moves it forward and adds one event to the series
  let(:time_zone) { 'Europe/Moscow' }
  let!(:meeting) do
    FactoryBot.create(:scheduled_meeting, room: room, name: 'Class', repeat: 'every_two_weeks',
                                          start_at: Time.utc(2026, 11, 4, 16, 6), duration: 3600,
                                          created_by_launch_nonce: app_launch.nonce,
                                          time_zone: time_zone)
  end

  # Last event of the series in the Moodle calendar; the job adds the next one,
  # two weeks later (2027-10-13 16:06 UTC)
  before do
    MoodleCalendarEvent.create!(event_id: 4395, scheduled_meeting_hash_id: meeting.hash_id,
                                start_at: Time.utc(2027, 9, 29, 16, 6))
    stub_request(:post, url).to_return(
      status: 200, body: { events: [{ id: 4396 }], warnings: [] }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  around do |example|
    travel_to(Time.utc(2026, 11, 11, 12, 0)) { example.run }
  end

  def sent_params(request)
    URI.decode_www_form(request.body).to_h
  end

  def expect_event_created(name)
    expect(
      a_request(:post, url).with do |req|
        body = sent_params(req)
        body['wsfunction'] == 'core_calendar_create_calendar_events' &&
          body['events[0][name]'] == name &&
          body['events[0][timestart]'] == Time.utc(2027, 10, 13, 16, 6).to_i.to_s
      end
    ).to have_been_made.once
  end

  it "prefixes the new event with the start time in the meeting's time zone, not the default one" do
    allow(Rails.configuration).to receive(:default_timezone).and_return('UTC')

    described_class.perform_now

    expect_event_created('19:06 - Class')
    expect(MoodleCalendarEvent.find_by(event_id: 4396)).to be_present
  end

  # meetings saved before the time zone was stored keep the old format
  context 'when the meeting has no time zone' do
    let(:time_zone) { nil }

    it 'adds the new event with the plain name' do
      described_class.perform_now

      expect_event_created('Class')
    end
  end
end
