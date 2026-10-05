require 'rails_helper'

RSpec.describe Moodle::API do
  let(:url) { 'https://moodle.example.com/webservice/rest/server.php' }
  let(:token) { 'moodle-token' }
  let(:moodle_token) { MoodleToken.new(url: url, token: token) }

  # Decodes the form body sent to Moodle into a flat hash, keeping bracketed
  # keys such as 'options[0][name]' as plain strings
  def sent_params(request)
    URI.decode_www_form(request.body).to_h
  end

  describe '.post' do
    let(:params) do
      { wstoken: token, wsfunction: 'core_webservice_get_site_info', moodlewsrestformat: 'json' }
    end

    it 'sends the params in the request body, not in the query string' do
      stub_request(:post, url).to_return(
        status: 200, body: '{"sitename": "Moodle"}', headers: { 'Content-Type' => 'application/json' }
      )

      result = described_class.post(url, params)

      expect(result).to include('sitename' => 'Moodle')
      expect(
        a_request(:post, url).with do |req|
          req.uri.query.nil? &&
            req.headers['Content-Type'] == 'application/x-www-form-urlencoded' &&
            sent_params(req) == {
              'wstoken' => token,
              'wsfunction' => 'core_webservice_get_site_info',
              'moodlewsrestformat' => 'json'
            }
        end
      ).to have_been_made.once
    end

    it 'sends the params in the body again when following a redirect' do
      redirect_url = 'https://moodle.example.com/moodle/webservice/rest/server.php'
      stub_request(:post, url).to_return(status: 302, headers: { 'Location' => redirect_url })
      stub_request(:post, redirect_url).to_return(
        status: 200, body: '{"sitename": "Moodle"}', headers: { 'Content-Type' => 'application/json' }
      )

      described_class.post(url, params)

      [url, redirect_url].each do |requested_url|
        expect(
          a_request(:post, requested_url).with { |req| req.uri.query.nil? && sent_params(req)['wstoken'] == token }
        ).to have_been_made.once
      end
    end

    context 'when the request fails' do
      # Avoids waiting between the retries
      before { allow(described_class).to receive(:sleep) }

      it 'raises UrlNotFoundError after retrying when Moodle answers 404' do
        stub_request(:post, url).to_return(status: 404)

        expect { described_class.post(url, params) }.to raise_error(Moodle::UrlNotFoundError)
        expect(a_request(:post, url)).to have_been_made.times(Moodle::API::MAX_RETRIES)
      end

      it 'raises RequestError when redirected to a different host' do
        stub_request(:post, url).to_return(
          status: 302, headers: { 'Location' => 'https://other.example.com/webservice/rest/server.php' }
        )

        expect { described_class.post(url, params) }.to raise_error(Moodle::RequestError)
        expect(a_request(:post, 'https://other.example.com/webservice/rest/server.php')).not_to have_been_made
      end
    end
  end

  describe '.create_calendar_event' do
    let(:app_launch) do
      FactoryBot.create(:app_launch, params: { 'cmid' => '329', 'resource_link_title' => 'Sala' })
    end
    let(:scheduled_meeting) do
      FactoryBot.build(:scheduled_meeting, name: 'Aula 1', description: 'Primeira aula',
                                           start_at: Time.zone.parse('2026-10-05 14:00'), duration: 3600,
                                           created_by_launch_nonce: app_launch.nonce)
    end

    # This is the call reported by the client: the HTML description with the
    # activity link made the query string even longer
    it 'sends the nested array params, including the HTML description, in the request body' do
      stub_request(:post, url).to_return(
        status: 200, body: { events: [{ id: 3580 }], warnings: [] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      expect(described_class.create_calendar_event(moodle_token, 'hash-id', scheduled_meeting, 30)).to be(true)
      expect(
        a_request(:post, url).with do |req|
          body = sent_params(req)
          req.uri.query.nil? &&
            body['wsfunction'] == 'core_calendar_create_calendar_events' &&
            body['events[0][name]'] == 'Aula 1' &&
            body['events[0][courseid]'] == '30' &&
            body['events[0][description]'].include?('<a href="https://moodle.example.com/mod/lti/view.php?id=329"')
        end
      ).to have_been_made.once
      expect(MoodleCalendarEvent.find_by(event_id: 3580)).to be_present
    end
  end

  describe '.delete_calendar_event' do
    it 'sends the nested array params in the request body' do
      stub_request(:post, url).to_return(
        status: 200, body: 'null', headers: { 'Content-Type' => 'application/json' }
      )

      expect(described_class.delete_calendar_event(moodle_token, 3580, 30, {})).to be(true)

      expect(
        a_request(:post, url).with do |req|
          req.uri.query.nil? &&
            sent_params(req).slice('wsfunction', 'events[0][eventid]', 'events[0][repeat]') == {
              'wsfunction' => 'core_calendar_delete_calendar_events',
              'events[0][eventid]' => '3580',
              'events[0][repeat]' => '0'
            }
        end
      ).to have_been_made.once
    end
  end

  describe '.get_course_attendance_instances' do
    it 'sends the nested array params in the request body' do
      stub_request(:post, url).to_return(
        status: 200,
        body: [{ modules: [{ modname: 'attendance', instance: 7, name: 'Presença' }] }].to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      result = described_class.get_course_attendance_instances(moodle_token, 30)

      expect(result).to eq([{ instance: 7, name: 'Presença' }])
      expect(
        a_request(:post, url).with do |req|
          req.uri.query.nil? &&
            sent_params(req).slice('wsfunction', 'courseid', 'options[0][name]', 'options[0][value]') == {
              'wsfunction' => 'core_course_get_contents',
              'courseid' => '30',
              'options[0][name]' => 'modname',
              'options[0][value]' => 'attendance'
            }
        end
      ).to have_been_made.once
    end
  end
end
