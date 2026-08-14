require 'rails_helper'

RSpec.describe MoodleAttendanceJob, type: :job do
  include ActiveJob::TestHelper

  let(:theme) { 'elos' }
  let(:locale) { 'en' }
  let(:course_id) { '12345' }
  let(:attendance_instance_id) { 500 }
  let(:session_id) { 555 }

  let(:room) { FactoryBot.create(:room) }
  let(:scheduled_meeting) do
    FactoryBot.create(:scheduled_meeting,
           room: room,
           name: 'Test Meeting',
           start_at: Time.zone.now)
  end

  let!(:consumer_config) { FactoryBot.create(:consumer_config, key: 'test_consumer_key_123') }
  let!(:moodle_token) do
    FactoryBot.create(:moodle_token,
           consumer_config: consumer_config,
           token: 'moodle_token_abc',
           url: 'https://moodle.example.com/webservice/rest/server.php')
  end

  let(:app_launch) do
    launch = FactoryBot.create(:app_launch, nonce: 'test_nonce_123')
    launch.params = {
      'user_id' => 'prefix_999',
      'context_id' => course_id,
      'custom_params' => {
        'oauth_consumer_key' => consumer_config.key
      }
    }
    launch.save!
    launch
  end

  let(:meeting_duration_seconds) { 3600 }
  let(:internal_meeting_id) { 'internal-meeting-id-test-1' }

  # Expected percentages (default threshold = 75%):
  # 100 -> 3000/3600 = 83.33% => Present
  # 200 -> 1800/3600 = 50.0%  => Partial presence (or Absent if no intermediate status)
  # 300 -> 0/3600 = 0%        => Absent
  # 400 -> no 'duration'     => binary fallback (Present) + warning
  # 500 -> never appears in attendees => Absent (enrolled but did not attend)
  let(:conference_data) do
    {
      'data' => {
        'metadata' => {
          'bbb_meeting_db_id' => scheduled_meeting.id.to_s,
          'bbb_launch_nonce' => app_launch.nonce,
          'bbb_oauth_consumer_key' => consumer_config.key
        },
        'start' => '2026-01-13T10:00:00Z',
        'duration' => meeting_duration_seconds,
        'attendees' => [
          { 'ext_user_id' => '999', 'moderator' => true, 'duration' => 3600 },
          { 'ext_user_id' => '100', 'moderator' => false, 'duration' => 3000 },
          { 'ext_user_id' => '200', 'moderator' => false, 'duration' => 1800 },
          { 'ext_user_id' => '300', 'moderator' => false, 'duration' => 0 },
          { 'ext_user_id' => '400', 'moderator' => false }
        ]
      },
      # top-level, sibling of 'data' -- matches the real BBB webhook payload shape.
      # Uniquely identifies a real meeting instance (unlike scheduled_meeting_id, which recurring
      # meetings reuse across every occurrence).
      'internal_meeting_id' => internal_meeting_id
    }
  end

  let(:conference_data_json) { conference_data.to_json }

  let(:enrolled_user_ids) { [100, 200, 300, 400, 500] }

  let(:two_statuses) do
    [
      { id: 1, description: 'Present', grade: 2 },
      { id: 2, description: 'Absent', grade: 0 }
    ]
  end

  let(:four_statuses) do
    [
      { id: 1, description: 'Present', grade: 2 },
      { id: 2, description: 'Late', grade: 1 },
      { id: 3, description: 'Excused', grade: 1 },
      { id: 4, description: 'Absent', grade: 0 }
    ]
  end

  before do
    allow(Resque.logger).to receive(:info)
    allow(Resque.logger).to receive(:error)
    allow(Resque.logger).to receive(:warn)

    allow(Moodle::API).to receive(:get_course_attendance_instances)
      .and_return([{ instance: attendance_instance_id, name: 'Presença' }])
    allow(Moodle::API).to receive(:get_session).and_return(nil)
    allow(Moodle::API).to receive(:add_session).and_return(session_id)
    allow(Moodle::API).to receive(:update_user_status).and_return(true)
    allow(Moodle::API).to receive(:get_enrolled_user_ids).and_return(enrolled_user_ids)
  end

  describe '#perform with the feature flag disabled (legacy binary behavior)' do
    before do
      moodle_token.update!(presence_percentage_enabled: false)
      allow(Moodle::API).to receive(:get_session_statuses).and_return(two_statuses)
    end

    it 'marks everyone in attendees as Present regardless of duration' do
      %w[999 100 200 300 400].each do |ext_user_id|
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, ext_user_id.to_i, '999', 1, 0
        )
      end

      described_class.perform_now(conference_data_json, theme, locale)
    end

    it 'marks enrolled users who are not in attendees as Absent' do
      expect(Moodle::API).to receive(:update_user_status).with(
        moodle_token, session_id, 500, '999', 2, 0
      )

      described_class.perform_now(conference_data_json, theme, locale)
    end

    it 'does not log any percentage-related warning' do
      expect(Resque.logger).not_to receive(:warn).with(/duration.*missing\/invalid/)

      described_class.perform_now(conference_data_json, theme, locale)
    end
  end

  describe '#perform with the feature flag enabled (percentage-based attendance)' do
    before do
      moodle_token.update!(presence_percentage_enabled: true, presence_threshold_percentage: 75)
    end

    context 'when the activity has an intermediate status available' do
      before do
        allow(Moodle::API).to receive(:get_session_statuses).and_return(four_statuses)
      end

      it 'marks a user with percentage >= threshold as Present' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 100, '999', 1, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'marks a user with 0% < percentage < threshold as Presença parcial' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 200, '999', 2, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'marks a user with percentage == 0 as Absent' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 300, '999', 4, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'marks an enrolled user who never joined as Absent' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 500, '999', 4, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'falls back to Present and logs a warning when duration is missing for an attendee' do
        expect(Resque.logger).to receive(:warn).with(
          /`duration` missing\/invalid in payload for ext_user_id=400/
        )
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 400, '999', 1, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'satisfies the gradebook invariant: every enrolled user gets some status' do
        enrolled_user_ids.each do |uid|
          expect(Moodle::API).to receive(:update_user_status).with(
            moodle_token, session_id, uid, '999', anything, 0
          )
        end

        described_class.perform_now(conference_data_json, theme, locale)
      end
    end

    context 'when the activity only has 2 distinct statuses (no intermediate one)' do
      before do
        allow(Moodle::API).to receive(:get_session_statuses).and_return(two_statuses)
      end

      it 'falls back to Absent for a user with 0% < percentage < threshold' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 200, '999', 2, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'still marks a user with percentage >= threshold as Present' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 100, '999', 1, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end
    end

    context 'when Late and Excused share the same grade (Moodle default status set)' do
      # Moodle creates the default set in the order Present, Absent, Late, Excused, so Late always
      # has the lower id, but both have grade 1 and the API may list them in any order. Only Late
      # is meant to be used as partial presence: Excused means the teacher justified the absence.
      let(:statuses_with_excused_first) do
        [
          { id: 10, description: 'Present', grade: 2 },
          { id: 11, description: 'Absent',  grade: 0 },
          { id: 13, description: 'Excused', grade: 1 },
          { id: 12, description: 'Late',    grade: 1 }
        ]
      end

      before do
        allow(Moodle::API).to receive(:get_session_statuses).and_return(statuses_with_excused_first)
      end

      it 'records partial presence as Late even when Excused comes first in the response' do
        # 200 -> 50%, between the partial and the full threshold
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 200, '999', 12, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'still resolves Present and Absent from the highest and lowest grades' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 100, '999', 10, 0
        )
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 300, '999', 11, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end
    end

    context 'when the total meeting duration is zero/missing' do
      let(:meeting_duration_seconds) { 0 }

      before do
        allow(Moodle::API).to receive(:get_session_statuses).and_return(four_statuses)
      end

      it 'falls back to the binary behavior (Present) for everyone in attendees' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 100, '999', 1, 0
        )
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 200, '999', 1, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end
    end

    context 'when an attendee duration slightly exceeds the meeting duration (clock skew)' do
      let(:conference_data) do
        data = super()
        # 900 -> 3700/3600 = 102.78% before clamping -- should be capped at 100%
        data['data']['attendees'] << { 'ext_user_id' => '900', 'moderator' => false, 'duration' => 3700 }
        data
      end
      let(:enrolled_user_ids) { [100, 200, 300, 400, 500, 900] }

      before do
        allow(Moodle::API).to receive(:get_session_statuses).and_return(four_statuses)
      end

      it 'clamps the percentage to 100% instead of logging a value above 100' do
        job = described_class.new
        attendee = { 'duration' => 3700 }

        expect(job.send(:attendee_percentage, attendee, 3600)).to eq(100.0)
      end

      it 'still marks the user as Present' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 900, '999', 1, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end
    end

    context 'when the threshold is customized per institution' do
      before do
        moodle_token.update!(presence_threshold_percentage: 40)
        allow(Moodle::API).to receive(:get_session_statuses).and_return(four_statuses)
      end

      it 'marks a user above the custom threshold as Present instead of Partial' do
        # 200 -> 50% >= 40% (custom threshold) => Present
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 200, '999', 1, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end
    end

    context 'when the partial threshold is left at its default (not explicitly configured)' do
      let(:conference_data) do
        data = super()
        # 800 -> 150/3600 = 4.17% (below the real default of 10%)
        data['data']['attendees'] << { 'ext_user_id' => '800', 'moderator' => false, 'duration' => 150 }
        data
      end
      let(:enrolled_user_ids) { [100, 200, 300, 400, 500, 800] }

      before do
        allow(Moodle::API).to receive(:get_session_statuses).and_return(four_statuses)
      end

      it 'defaults partial_presence_threshold_percentage to 10' do
        expect(moodle_token.partial_presence_threshold_percentage).to eq(10)
      end

      it 'marks a user below the default 10% partial threshold as Absent, not Partial' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 800, '999', 4, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end
    end

    context 'when a minimum partial-presence threshold is configured' do
      let(:conference_data) do
        data = super()
        # 600 -> 90/3600 = 2.5%  (below the 30% partial threshold)
        # 700 -> 1080/3600 = 30% (exactly at the partial threshold)
        data['data']['attendees'] << { 'ext_user_id' => '600', 'moderator' => false, 'duration' => 90 }
        data['data']['attendees'] << { 'ext_user_id' => '700', 'moderator' => false, 'duration' => 1080 }
        data
      end
      let(:enrolled_user_ids) { [100, 200, 300, 400, 500, 600, 700] }

      before do
        moodle_token.update!(partial_presence_threshold_percentage: 30)
        allow(Moodle::API).to receive(:get_session_statuses).and_return(four_statuses)
      end

      it 'marks a user below the partial threshold (but above 0%) as Absent instead of Partial' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 600, '999', 4, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'marks a user exactly at the partial threshold as Partial' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 700, '999', 2, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'still marks a user between the partial threshold and the full threshold as Partial' do
        # 200 -> 50% is between 30% (partial) and 75% (full) => Partial
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 200, '999', 2, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'still marks a user at/above the full threshold as Present' do
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 100, '999', 1, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end

      it 'still marks a user with percentage == 0 as Absent, not Partial' do
        # partial_threshold defaults would not apply here: 0% is always Absent regardless
        expect(Moodle::API).to receive(:update_user_status).with(
          moodle_token, session_id, 300, '999', 4, 0
        )

        described_class.perform_now(conference_data_json, theme, locale)
      end
    end
  end

  describe 'idempotency of Moodle session creation' do
    before do
      allow(Moodle::API).to receive(:get_session_statuses).and_return(two_statuses)
    end

    it 'creates a new session and stores its id and internal_meeting_id on the first run' do
      described_class.perform_now(conference_data_json, theme, locale)

      expect(Moodle::API).to have_received(:add_session).once
      scheduled_meeting.reload
      expect(scheduled_meeting.moodle_attendance_session_id).to eq(session_id)
      expect(scheduled_meeting.moodle_attendance_internal_meeting_id).to eq(internal_meeting_id)
    end

    it 'reuses the stored session id on a retry of the SAME occurrence (same internal_meeting_id)' do
      described_class.perform_now(conference_data_json, theme, locale)

      allow(Moodle::API).to receive(:get_session).with(moodle_token, session_id).and_return(
        { 'id' => session_id, 'statuses' => two_statuses }
      )

      described_class.perform_now(conference_data_json, theme, locale)

      expect(Moodle::API).to have_received(:add_session).once
    end

    it 'creates a new session if the previously stored one no longer exists on Moodle' do
      described_class.perform_now(conference_data_json, theme, locale)

      allow(Moodle::API).to receive(:get_session).with(moodle_token, session_id).and_return(nil)
      allow(Moodle::API).to receive(:add_session).and_return(556)

      described_class.perform_now(conference_data_json, theme, locale)

      expect(Moodle::API).to have_received(:add_session).twice
      expect(scheduled_meeting.reload.moodle_attendance_session_id).to eq(556)
    end

    # Regression test: a recurring ScheduledMeeting reuses the SAME scheduled_meeting_id across
    # every occurrence (week 1, week 2, ...). Before this fix, idempotency was keyed only by
    # scheduled_meeting_id, so a second, entirely different real meeting would incorrectly reuse
    # (and silently overwrite) the first occurrence's Moodle session.
    it 'creates a NEW session -- and does not overwrite the previous one -- for a different occurrence of a recurring meeting (different internal_meeting_id)' do
      described_class.perform_now(conference_data_json, theme, locale)
      expect(scheduled_meeting.reload.moodle_attendance_session_id).to eq(session_id)

      # the first occurrence's session is still technically valid on Moodle...
      allow(Moodle::API).to receive(:get_session).with(moodle_token, session_id).and_return(
        { 'id' => session_id, 'statuses' => two_statuses }
      )
      allow(Moodle::API).to receive(:add_session).and_return(556)

      next_occurrence_data = conference_data.dup
      next_occurrence_data['internal_meeting_id'] = 'internal-meeting-id-test-2-different-occurrence'

      described_class.perform_now(next_occurrence_data.to_json, theme, locale)

      expect(Moodle::API).to have_received(:add_session).twice
      scheduled_meeting.reload
      expect(scheduled_meeting.moodle_attendance_session_id).to eq(556)
      expect(scheduled_meeting.moodle_attendance_internal_meeting_id).to eq('internal-meeting-id-test-2-different-occurrence')
    end

    it 'never reuses a stored session when internal_meeting_id is missing from the payload (defensive fallback)' do
      described_class.perform_now(conference_data_json, theme, locale)

      data_without_internal_id = conference_data.dup
      data_without_internal_id.delete('internal_meeting_id')
      allow(Moodle::API).to receive(:add_session).and_return(557)

      described_class.perform_now(data_without_internal_id.to_json, theme, locale)

      expect(Moodle::API).to have_received(:add_session).twice
    end
  end

  describe '#perform with invalid/missing top-level data' do
    it 'logs error and returns early when bbb_meeting_db_id is missing' do
      data = conference_data.dup
      data['data']['metadata'].delete('bbb_meeting_db_id')

      expect(Resque.logger).to receive(:error).with(
        /Could not find 'bbb_meeting_db_id' in conference_data metadata/
      )

      described_class.perform_now(data.to_json, theme, locale)
    end

    it 'logs error and returns early when ConsumerConfig cannot be found' do
      data = conference_data.dup
      data['data']['metadata']['bbb_oauth_consumer_key'] = 'nonexistent_key'

      expect(Resque.logger).to receive(:error).with(
        /Could not find ConsumerConfig with key 'nonexistent_key'/
      )

      described_class.perform_now(data.to_json, theme, locale)
    end
  end
end
