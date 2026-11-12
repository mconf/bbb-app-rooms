# frozen_string_literal: true

require 'rails_helper'

describe RoomsController, type: :controller do
  let(:room) { FactoryBot.create(:room) }

  describe '#setup_consumer_configs' do
    let(:consumer_key) { 'rooms-controller-spec-key' }
    # The broker always sends the not-null configs
    let(:broker_params) do
      {
        'oauth_consumer_key' => consumer_key,
        'allow_student_scheduling' => false,
        'allow_ai_artifacts' => true,
        'hide_recordings_history' => false,
        'auto_start_recording' => false,
      }
    end

    def launch_with(custom_params)
      params = { 'custom_params' => broker_params.merge(custom_params) }
      app_launch = AppLaunch.new(params: params)
      controller.instance_variable_set(:@app_launch, app_launch)
      controller.send(:setup_consumer_configs)
      ConsumerConfig.find_by(key: consumer_key)
    end

    it 'stores allow_large_meetings sent by the broker' do
      config = launch_with('allow_large_meetings' => true)

      expect(config.allow_large_meetings).to be(true)
    end

    it 'turns allow_large_meetings off when the broker sends it disabled' do
      FactoryBot.create(:consumer_config, key: consumer_key, allow_large_meetings: true)

      config = launch_with('allow_large_meetings' => false)

      expect(config.allow_large_meetings).to be(false)
    end

    # Brokers that predate the flag do not send it at all
    it 'defaults allow_large_meetings to false when the broker does not send it' do
      config = launch_with({})

      expect(config.allow_large_meetings).to be(false)
    end
  end
end
