require 'rails_helper'

describe ScheduledMeetingsController, type: :controller do
  describe '#scheduled_meeting_params' do
    let(:consumer_config) { FactoryBot.create(:consumer_config, key: 'scheduled-meetings-controller-spec') }
    let(:room) { FactoryBot.create(:room, consumer_key: consumer_config.key) }

    before do
      controller.params = ActionController::Parameters.new(
        scheduled_meeting: { name: 'Webinar', large_meeting: '1' }
      )
    end

    it 'permits large_meeting when the institution allows large meetings' do
      consumer_config.update!(allow_large_meetings: true)

      expect(controller.send(:scheduled_meeting_params, room).to_h).to include('large_meeting' => '1')
    end

    # A disabled checkbox is not submitted, but the request can still be forged
    it 'drops large_meeting when the institution does not allow large meetings' do
      consumer_config.update!(allow_large_meetings: false)

      expect(controller.send(:scheduled_meeting_params, room)).not_to have_key('large_meeting')
    end
  end
end
