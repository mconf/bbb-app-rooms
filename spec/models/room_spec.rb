require 'rails_helper'
require 'spec_helper'

RSpec.describe Room, type: :model do

  it "creates a new instance given valid attributes" do
    expect(FactoryBot.build(:room)).to be_valid
  end

  describe '#can_mark_moodle_attendance' do
    let(:room) { FactoryBot.create(:room) }

    it 'asks the Moodle API only once per instance' do
      expect(Moodle::API).to receive(:token_functions_configured?).once.and_return(true)

      room.can_mark_moodle_attendance
      room.can_mark_moodle_attendance
      room.moodle_attendance_tooltip_key
    end

    it 'memoizes a negative answer as well' do
      expect(Moodle::API).to receive(:token_functions_configured?).once.and_return(false)

      expect(room.can_mark_moodle_attendance).to be(false)
      expect(room.can_mark_moodle_attendance).to be(false)
    end
  end

  describe '#moodle_attendance_tooltip_key' do
    let(:consumer_config) { FactoryBot.create(:consumer_config, key: 'room-spec-consumer-key') }
    let(:room) { FactoryBot.create(:room, consumer_key: consumer_config.key) }
    let!(:moodle_token) { FactoryBot.create(:moodle_token, consumer_config: consumer_config) }

    it 'returns the disabled key when attendance cannot be marked' do
      allow(Moodle::API).to receive(:token_functions_configured?).and_return(false)

      expect(room.moodle_attendance_tooltip_key).to eq(:mark_moodle_attendance_disabled)
    end

    it 'returns the percentage key when the institution has the feature enabled' do
      allow(Moodle::API).to receive(:token_functions_configured?).and_return(true)
      moodle_token.update!(presence_percentage_enabled: true)

      expect(room.moodle_attendance_tooltip_key).to eq(:mark_moodle_attendance_percentage)
    end

    it 'returns the binary key when the institution does not have the feature enabled' do
      allow(Moodle::API).to receive(:token_functions_configured?).and_return(true)
      moodle_token.update!(presence_percentage_enabled: false)

      expect(room.moodle_attendance_tooltip_key).to eq(:mark_moodle_attendance)
    end
  end

  describe '#params_for_get_all_meetings' do
    let(:room) { FactoryBot.create(:room) }

    it 'returns the correct parameters for getting all meetings' do
      expect(room.params_for_get_all_meetings).to eq({roomHandlerID: room.handler})
    end
  end

end
