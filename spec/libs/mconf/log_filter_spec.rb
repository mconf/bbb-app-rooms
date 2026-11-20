# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mconf::LogFilter do
  let(:bbb_secret) { 'Xq7tR2mK9vLp4nW8sB3hJ6dF1gC5zY0aE2uTiOo4Pk' }

  describe '.mask' do
    it 'keeps a 7-char prefix of a long value' do
      expect(described_class.mask(bbb_secret)).to eq('Xq7tR2m[FILTERED]')
    end

    it 'hides a short value entirely' do
      expect(described_class.mask('secret123')).to eq('[FILTERED]')
    end
  end

  describe '.filter' do
    let(:params) do
      {
        'user_id' => '28417',
        'lis_person_contact_email_primary' => 'carla@escola.edu',
        'custom_params' => {
          'bbb' => { 'url' => 'https://bbb.example.com/bigbluebutton/', 'secret' => bbb_secret },
          'moodle' => { 'url' => 'https://moodle.example.com', 'token' => '3e9d7b1c5a0f4e82b6c4d9a17f2e5b30' },
          'brightspace' => { 'oauth_client_secret' => 'short' }
        }
      }
    end

    subject(:filtered) { described_class.filter(params) }

    it 'masks credentials at any depth' do
      expect(filtered['custom_params']['bbb']['secret']).to eq('Xq7tR2m[FILTERED]')
      expect(filtered['custom_params']['moodle']['token']).to eq('3e9d7b1[FILTERED]')
      expect(filtered['custom_params']['brightspace']['oauth_client_secret']).to eq('[FILTERED]')
    end

    it 'keeps everything else, personal data included' do
      expect(filtered['user_id']).to eq('28417')
      expect(filtered['lis_person_contact_email_primary']).to eq('carla@escola.edu')
      expect(filtered['custom_params']['bbb']['url']).to eq('https://bbb.example.com/bigbluebutton/')
    end

    it 'does not change the original hash' do
      filtered
      expect(params['custom_params']['bbb']['secret']).to eq(bbb_secret)
    end
  end
end
