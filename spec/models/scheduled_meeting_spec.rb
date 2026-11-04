require 'rails_helper'

RSpec.describe ScheduledMeeting, type: :model do

  context "creates a new instance" do
    let(:room) { FactoryBot.create(:room) }

    it "given valid attributes" do
      expect(FactoryBot.build(:scheduled_meeting, room: room)).to be_valid
    end

    it "given invalid attributes with room nil" do
      expect(FactoryBot.build(:scheduled_meeting, room: nil)).not_to be_valid
    end
  end

  describe '#will_be_large_meeting?' do
    let(:consumer_config) { FactoryBot.create(:consumer_config, key: 'scheduled-meeting-spec-large') }
    let(:room) { FactoryBot.create(:room, consumer_key: consumer_config.key) }

    [
      [true,  true,  true],
      [true,  false, false],
      [false, true,  false],
      [false, false, false],
    ].each do |large_meeting, allowed, expected|
      it "returns #{expected} when large_meeting is #{large_meeting} and the institution allows it is #{allowed}" do
        consumer_config.update!(allow_large_meetings: allowed)
        meeting = FactoryBot.build(:scheduled_meeting, room: room, large_meeting: large_meeting)

        expect(meeting.will_be_large_meeting?).to be(expected)
      end
    end
  end

  describe '#create_options' do
    let(:consumer_config) { FactoryBot.create(:consumer_config, key: 'scheduled-meeting-spec-options') }
    let(:room) { FactoryBot.create(:room, consumer_key: consumer_config.key) }
    let(:user) { User.new(uid: 'u-1', roles: 'Instructor', launch_nonce: 'no-launch') }

    it 'sends the large meeting metadata as true when the meeting is large and allowed' do
      consumer_config.update!(allow_large_meetings: true)
      meeting = FactoryBot.create(:scheduled_meeting, room: room, large_meeting: true)

      expect(meeting.create_options(user)['meta_bbb-large-meeting']).to be(true)
    end

    it 'does not send the large meeting metadata when the meeting is not large' do
      consumer_config.update!(allow_large_meetings: true)
      meeting = FactoryBot.create(:scheduled_meeting, room: room, large_meeting: false)

      expect(meeting.create_options(user)).not_to have_key('meta_bbb-large-meeting')
    end

    it 'does not send the large meeting metadata when the institution does not allow large meetings' do
      consumer_config.update!(allow_large_meetings: false)
      meeting = FactoryBot.create(:scheduled_meeting, room: room, large_meeting: false)

      expect(meeting.create_options(user)).not_to have_key('meta_bbb-large-meeting')
    end

    # A meeting scheduled while the institution had the permission must not keep it
    it 'does not send the large meeting metadata when the institution lost the permission' do
      meeting = FactoryBot.create(:scheduled_meeting, room: room, large_meeting: true)
      consumer_config.update!(allow_large_meetings: false)

      expect(meeting.create_options(user)).not_to have_key('meta_bbb-large-meeting')
    end
  end

end
