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

  describe '#check_all_moderators' do
    let(:room) { FactoryBot.create(:room) }

    it 'returns the value set in the meeting when the room allows changing it' do
      room.update!(allow_all_moderators: true)
      meeting = FactoryBot.build(:scheduled_meeting, room: room, all_moderators: true)

      expect(meeting.check_all_moderators).to be(true)
    end

    it 'returns the default value when the room does not allow changing it' do
      room.update!(allow_all_moderators: false)
      meeting = FactoryBot.build(:scheduled_meeting, room: room, all_moderators: true)

      expect(meeting.check_all_moderators).to be(false)
    end
  end

  describe '#check_wait_moderator' do
    let(:room) { FactoryBot.create(:room) }

    it 'returns the value set in the meeting when the room allows changing it' do
      room.update!(allow_wait_moderator: true)
      meeting = FactoryBot.build(:scheduled_meeting, room: room, wait_moderator: false)

      expect(meeting.check_wait_moderator).to be(false)
    end

    it 'returns the default value when the room does not allow changing it' do
      room.update!(allow_wait_moderator: false)
      meeting = FactoryBot.build(:scheduled_meeting, room: room, wait_moderator: false)

      expect(meeting.check_wait_moderator).to be(true)
    end
  end

  describe '#will_auto_start_recording?' do
    let(:consumer_config) { FactoryBot.create(:consumer_config, key: 'scheduled-meeting-spec-auto-start') }
    let(:room) { FactoryBot.create(:room, consumer_key: consumer_config.key) }

    [
      [true,  true,  true,  true],
      [false, true,  true,  false],
      [true,  false, true,  false],
      [true,  true,  false, false],
    ].each do |recording, auto_start, allowed, expected|
      it "returns #{expected} when recording is #{recording}, auto_start_recording is #{auto_start} " \
         "and the institution allows it is #{allowed}" do
        consumer_config.update!(auto_start_recording: allowed)
        meeting = FactoryBot.build(:scheduled_meeting, room: room, recording: recording, auto_start_recording: auto_start)

        expect(meeting.will_auto_start_recording?).to be(expected)
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

    it 'sends the meeting settings as standard API params' do
      meeting = FactoryBot.create(:scheduled_meeting, room: room, recording: true, auto_start_recording: true,
                                                      disable_private_chat: true, disable_note: false)

      expect(meeting.create_options(user)).to include(
        moderatorPW: room.moderator,
        attendeePW: room.viewer,
        welcome: meeting.welcome,
        record: true,
        autoStartRecording: false,
        lockSettingsDisablePrivateChat: true,
        lockSettingsDisableNote: false
      )
    end

    it 'sends the meeting identification metadata' do
      meeting = FactoryBot.create(:scheduled_meeting, room: room)

      expect(meeting.create_options(user)).to include(
        'meta_bbb-origin' => 'LTI',
        'meta_bbb-recording-name' => meeting.name,
        'meta_bbb-recording-description' => meeting.description,
        'meta_bbb-room-handler' => room.handler,
        'meta_bbb-meeting-db-id' => meeting.id
      )
    end

    context 'with the duration configured by the institution' do
      let(:meeting) { FactoryBot.create(:scheduled_meeting, room: room, duration: 3600) }

      it 'sends the duration plus one hour when set_duration is enabled' do
        consumer_config.update!(set_duration: true)

        expect(meeting.create_options(user)[:duration]).to eq(120)
      end

      it 'does not send a duration when set_duration is disabled' do
        consumer_config.update!(set_duration: false)

        expect(meeting.create_options(user)).not_to have_key(:duration)
      end
    end

    context 'with the launch that started the meeting' do
      let(:app_launch) do
        AppLaunch.create!(
          nonce: 'create-options-nonce',
          params: {
            'tool_consumer_info_product_family_code' => 'moodle',
            'tool_consumer_info_version' => '4.1',
            'lti_version' => 'LTI-1p0',
            'lis_outcome_service_url' => 'https://moodle.escola.edu/mod/lti/service.php',
            'context_id' => '42',
            'context_title' => 'Cálculo I',
            'context_label' => 'CALC1',
            'resource_link_title' => 'Aula ao vivo',
            'custom_params' => { 'oauth_consumer_key' => consumer_config.key },
          }
        )
      end
      let(:user) { User.new(uid: 'u-1', roles: 'Instructor', launch_nonce: app_launch.nonce) }

      it 'sends the origin metadata taken from the launch' do
        meeting = FactoryBot.create(:scheduled_meeting, room: room)

        expect(meeting.create_options(user)).to include(
          'meta_bbb-origin-server-name' => 'moodle',
          'meta_bbb-origin-server-url' => 'moodle.escola.edu',
          'meta_bbb-origin-version' => '4.1',
          'meta_bbb-origin-lti-version' => 'LTI-1p0',
          'meta_bbb-context-id' => '42',
          'meta_bbb-context-title' => 'Cálculo I',
          'meta_bbb-context-label' => 'CALC1',
          'meta_bbb-resource_link_title' => 'Aula ao vivo',
          'meta_bbb-launch-nonce' => 'create-options-nonce',
          'meta_bbb-oauth-consumer-key' => consumer_config.key
        )
      end
    end

    it 'does not send origin metadata when the launch is not found' do
      meeting = FactoryBot.create(:scheduled_meeting, room: room)

      expect(meeting.create_options(user).keys).not_to include('meta_bbb-origin-server-name', 'meta_bbb-launch-nonce')
    end

    context 'with Moodle group selection' do
      let(:meeting) do
        FactoryBot.create(:scheduled_meeting, room: room, moodle_group_id: 7, moodle_group_name: 'Turma A')
      end

      it 'sends the Moodle group metadata when group selection is enabled' do
        FactoryBot.create(:moodle_token, consumer_config: consumer_config, group_select_enabled: true)

        expect(meeting.create_options(user)).to include(
          'meta_bbb-moodle-group-id' => 7,
          'meta_bbb-moodle-group-name' => 'Turma A'
        )
      end

      it 'does not send the Moodle group metadata when group selection is disabled' do
        FactoryBot.create(:moodle_token, consumer_config: consumer_config, group_select_enabled: false)

        expect(meeting.create_options(user).keys).not_to include('meta_bbb-moodle-group-id', 'meta_bbb-moodle-group-name')
      end
    end
  end

end
