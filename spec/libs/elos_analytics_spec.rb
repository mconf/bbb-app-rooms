# frozen_string_literal: true

require 'rails_helper'
require './lib/mconf/dash_mr'

describe Mconf::DashMr do
  let(:consumer_config) { FactoryBot.create(:consumer_config, institution_guid: 'guid-1', allow_dash_mr: true) }
  let(:room) { FactoryBot.create(:room, handler: 'handler-1', consumer_key: consumer_config.key) }
  let(:user) do
    User.new(uid: 'u-42', full_name: 'Carla Menezes', email: 'carla@escola.edu', roles: 'Instructor')
  end
  let(:app_launch) { AppLaunch.new(params: { 'context_id' => 'mat101' }) }

  def decoded(token)
    JWT.decode(token, nil, true, algorithms: ['RS256'],
                                 jwks: JWT::JWK::Set.new(LaunchSigningKey.key_set))
  end

  before do
    allow(Rails.configuration).to receive(:dash_mr_launch_url).and_return('http://dash.test/launch')
    allow(Rails.configuration).to receive(:dash_mr_issuer).and_return('rooms')
    allow(Rails.configuration).to receive(:dash_mr_audience).and_return('dash-mr')
    allow(Rails.configuration).to receive(:dash_mr_token_ttl).and_return(60)
  end

  describe '.launch_token' do
    subject(:token) { described_class.launch_token(room: room, user: user, app_launch: app_launch) }

    it 'carries the claims the dashboard checks' do
      payload, = decoded(token)

      expect(payload['iss']).to eq('rooms')
      expect(payload['aud']).to eq('dash-mr')
      expect(payload['sub']).to eq('lti:mat101:u-42')
      expect(payload['exp'] - payload['iat']).to eq(60)
    end

    it 'carries the context the dashboard runs on' do
      payload, = decoded(token)

      expect(payload['scope']).to eq(
        'type' => 'lti_context', 'consumer_key' => consumer_config.key,
        'handler' => 'handler-1', 'institution_guid' => 'guid-1'
      )
      expect(payload['name']).to eq('Carla Menezes')
      expect(payload['email']).to eq('carla@escola.edu')
    end

    it 'names the key that signed it, so the dashboard knows which one to verify with' do
      _, header = decoded(token)

      expect(header['kid']).to eq(LaunchSigningKey.current.kid)
      expect(header['alg']).to eq('RS256')
    end

    # The dashboard refuses a token whose jti it has already seen, so two launches
    # sharing one would make the second fail
    it 'is a different token every time' do
      first, = decoded(described_class.launch_token(room: room, user: user, app_launch: app_launch))
      second, = decoded(described_class.launch_token(room: room, user: user, app_launch: app_launch))

      expect(first['jti']).not_to eq(second['jti'])
    end

    # LTI sends roles either plain or as a URN; the dashboard compares plain names
    it 'sends roles as plain lowercase names' do
      user.roles = 'urn:lti:role:ims/lis/Instructor,Learner'

      payload, = decoded(token)

      expect(payload['roles']).to eq(%w[instructor learner])
    end

    it 'falls back to the room handler when the launch has no context' do
      payload, = decoded(described_class.launch_token(room: room, user: user, app_launch: nil))

      expect(payload['sub']).to eq('lti:handler-1:u-42')
    end

    # Rooms created before the column existed still have it blank. Room#institution_guid
    # looks the config up by that same column, so both values have to come from the key
    # the fallback resolves, or a legacy room hands over half a context.
    it 'falls back to the last launch for the consumer key, and for the guid with it' do
      FactoryBot.create(:consumer_config, key: 'legacy-key', institution_guid: 'legacy-guid', allow_dash_mr: true)
      room.update!(consumer_key: nil)
      FactoryBot.create(
        :app_launch, room_handler: room.handler,
                     params: { 'custom_params' => { 'oauth_consumer_key' => 'legacy-key' } }
      )

      payload, = decoded(token)

      expect(payload['scope']['consumer_key']).to eq('legacy-key')
      expect(payload['scope']['institution_guid']).to eq('legacy-guid')
    end

    it 'refuses to issue a token the dashboard could not key its analytics with' do
      room.update!(consumer_key: nil)

      expect { token }.to raise_error(described_class::ConfigurationError, /consumer key/)
    end

    it 'refuses to issue a token when there is nowhere to send it' do
      allow(Rails.configuration).to receive(:dash_mr_launch_url).and_return('')

      expect { token }.to raise_error(described_class::ConfigurationError, /LAUNCH_URL/)
    end

    it 'refuses to issue a token the dashboard could not scope to an institution' do
      consumer_config.update!(institution_guid: nil)

      expect { token }.to raise_error(described_class::ConfigurationError, /institution guid/)
    end

    # This is the boundary that matters: whoever the caller is, an institution that was
    # never enabled on the broker must not get a token minted for it.
    it 'refuses to issue a token for an institution that was not enabled' do
      consumer_config.update!(allow_dash_mr: false)

      expect { token }.to raise_error(described_class::ConfigurationError, /does not have the dashboard enabled/)
    end
  end
end
