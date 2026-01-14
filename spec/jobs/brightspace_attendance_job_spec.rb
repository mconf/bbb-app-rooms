require 'rails_helper'

RSpec.describe BrightspaceAttendanceJob, type: :job do
  include ActiveJob::TestHelper

  let(:base_url) { 'https://example.brightspace.com' }
  let(:access_token) { 'test_access_token_123' }
  let(:course_id) { '12345' }
  let(:locale) { 'en' }

  let(:room) { FactoryBot.create(:room) }
  let(:scheduled_meeting) do
    FactoryBot.create(:scheduled_meeting,
           room: room,
           name: 'Test Meeting',
           start_at: Time.zone.now)
  end

  let!(:consumer_config) { FactoryBot.create(:consumer_config, key: 'test_consumer_key_123') }
  let!(:brightspace_oauth) do
    FactoryBot.create(:consumer_config_brightspace_oauth,
           consumer_config: consumer_config,
           url: base_url)
  end

  let(:app_launch) do
    launch = FactoryBot.create(:app_launch,
                    nonce: 'test_nonce_123')
    launch.params = {
      'user_id' => 'prefix_999',
      'lis_person_contact_email_primary' => 'instructor@example.com',
      'roles' => 'Instructor',
      'context_id' => course_id,
      'custom_params' => {
        'oauth_consumer_key' => consumer_config.key
      }
    }
    launch.omniauth_auth = {
      'brightspace' => {
        'credentials' => {
          'token' => access_token
        }
      }
    }
    launch.save!
    launch
  end

  let(:conference_data) do
    {
      'data' => {
        'metadata' => {
          'bbb_meeting_db_id' => scheduled_meeting.id.to_s,
          'bbb_launch_nonce' => app_launch.nonce
        },
        'start' => '2026-01-13T10:00:00Z',
        'attendees' => [
          { 'ext_user_id' => 'prefix_100', 'name' => 'Student 1' },
          { 'ext_user_id' => 'prefix_200', 'name' => 'Student 2' },
          { 'ext_user_id' => 'prefix_999', 'name' => 'Instructor' } # Should be filtered out
        ]
      }
    }
  end

  let(:conference_data_json) { conference_data.to_json }

  let(:brightspace_client) { instance_double(Mconf::BrightspaceClient) }

  let(:grade_categories) do
    [
      { 'Id' => 10, 'Name' => 'Presença nas aulas online' },
      { 'Id' => 11, 'Name' => 'Other Category' }
    ]
  end

  let(:grade_object) do
    { 'Id' => 101, 'Name' => 'Attendance 01-13-2026' }
  end

  let(:enrolled_users_page1) do
    {
      'Objects' => [
        { 'Identifier' => 100, 'DisplayName' => 'Student 1' },
        { 'Identifier' => 200, 'DisplayName' => 'Student 2' },
        { 'Identifier' => 300, 'DisplayName' => 'Student 3' }
      ],
      'Next' => nil
    }
  end

  before do
    allow(Mconf::BrightspaceClient).to receive(:new).and_return(brightspace_client)
    allow(Resque.logger).to receive(:info)
    allow(Resque.logger).to receive(:error)
    allow(Resque.logger).to receive(:warn)
  end

  describe '#perform' do
    context 'with valid conference data' do
      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).and_return(enrolled_users_page1)
      end

      it 'executes successfully and marks attendance' do
        expect {
          described_class.perform_now(conference_data_json, locale)
        }.not_to raise_error
      end

      it 'initializes BrightspaceClient with correct parameters' do
        expect(Mconf::BrightspaceClient).to receive(:new).with(
          base_url,
          access_token,
          logger: Resque.logger
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'retrieves grade categories from the course' do
        expect(brightspace_client).to receive(:get_course_grade_categories).with(course_id)

        described_class.perform_now(conference_data_json, locale)
      end

      it 'creates a grade object with the correct date' do
        expect(brightspace_client).to receive(:create_grade_object).with(
          course_id,
          10, # category ID
          hash_including(name: /Attendance/, short_name: anything)
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'assigns max grade to present students' do
        expect(brightspace_client).to receive(:update_grade_value).with(
          course_id,
          grade_object_id: 101,
          user_id: 100,
          grade_value: Mconf::BrightspaceClient::MaxGrade,
          grade_comment: anything
        )
        expect(brightspace_client).to receive(:update_grade_value).with(
          course_id,
          grade_object_id: 101,
          user_id: 200,
          grade_value: Mconf::BrightspaceClient::MaxGrade,
          grade_comment: anything
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'assigns grade 0 to absent students' do
        expect(brightspace_client).to receive(:update_grade_value).with(
          course_id,
          grade_object_id: 101,
          user_id: 300,
          grade_value: 0,
          grade_comment: anything
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'does not assign grade to the instructor' do
        expect(brightspace_client).not_to receive(:update_grade_value).with(
          anything,
          hash_including(user_id: 999)
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'logs attendance marking summary' do
        expect(Resque.logger).to receive(:info).with(
          /Attendance marking summary.*Total = 3.*Present.*Absent/
        )

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'when grade category does not exist' do
      let(:new_category) { { 'Id' => 99, 'Name' => 'Presença nas aulas online' } }

      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return([])
        allow(brightspace_client).to receive(:create_course_grade_category).and_return(new_category)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).and_return(enrolled_users_page1)
      end

      it 'creates a new grade category' do
        expect(brightspace_client).to receive(:create_course_grade_category).with(
          course_id,
          hash_including(name: 'Presença nas aulas online')
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'uses the new category ID for grade object creation' do
        expect(brightspace_client).to receive(:create_grade_object).with(
          course_id,
          99,
          anything
        )

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'when grade category creation fails' do
      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return([])
        allow(brightspace_client).to receive(:create_course_grade_category).and_return(nil)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).and_return(enrolled_users_page1)
      end

      it 'logs a warning and continues without category' do
        expect(Resque.logger).to receive(:warn).with(
          /Failed to create grade category for attendances, proceeding without it/
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'creates grade object with nil category ID' do
        expect(brightspace_client).to receive(:create_grade_object).with(
          course_id,
          nil,
          anything
        )

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'when grade object creation fails' do
      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(nil)
      end

      it 'logs error and aborts the job' do
        expect(Resque.logger).to receive(:error).with(
          /Grade Object.*could not be created, aborting job/
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'does not attempt to update any grades' do
        expect(brightspace_client).not_to receive(:update_grade_value)

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'with paginated enrolled users' do
      let(:enrolled_users_page1) do
        {
          'Objects' => [
            { 'Identifier' => 100, 'DisplayName' => 'Student 1' },
            { 'Identifier' => 200, 'DisplayName' => 'Student 2' }
          ],
          'Next' => 'https://example.brightspace.com/next-page'
        }
      end

      let(:enrolled_users_page2) do
        {
          'Objects' => [
            { 'Identifier' => 300, 'DisplayName' => 'Student 3' },
            { 'Identifier' => 400, 'DisplayName' => 'Student 4' }
          ],
          'Next' => nil
        }
      end

      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).with(course_id)
                                                                .and_return(enrolled_users_page1)
        allow(brightspace_client).to receive(:get_course_users)
          .with(course_id, next_page_url: 'https://example.brightspace.com/next-page')
          .and_return(enrolled_users_page2)
      end

      it 'retrieves all pages of enrolled users' do
        expect(brightspace_client).to receive(:get_course_users).twice

        described_class.perform_now(conference_data_json, locale)
      end

      it 'assigns grades to students from all pages' do
        # Present students
        expect(brightspace_client).to receive(:update_grade_value).with(
          anything,
          hash_including(user_id: 100, grade_value: Mconf::BrightspaceClient::MaxGrade)
        )
        expect(brightspace_client).to receive(:update_grade_value).with(
          anything,
          hash_including(user_id: 200, grade_value: Mconf::BrightspaceClient::MaxGrade)
        )
        # Absent students
        expect(brightspace_client).to receive(:update_grade_value).with(
          anything,
          hash_including(user_id: 300, grade_value: 0)
        )
        expect(brightspace_client).to receive(:update_grade_value).with(
          anything,
          hash_including(user_id: 400, grade_value: 0)
        )

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'when pagination fails on second page' do
      let(:enrolled_users_page1) do
        {
          'Objects' => [
            { 'Identifier' => 100, 'DisplayName' => 'Student 1' }
          ],
          'Next' => 'https://example.brightspace.com/next-page'
        }
      end

      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).with(course_id)
                                                                .and_return(enrolled_users_page1)
        allow(brightspace_client).to receive(:get_course_users)
          .with(course_id, next_page_url: 'https://example.brightspace.com/next-page')
          .and_return(nil)
      end

      it 'logs error and stops pagination' do
        expect(Resque.logger).to receive(:error).with(
          /Failed to retrieve a page of enrolled users, stopping pagination/
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'still processes students from first page' do
        expect(brightspace_client).to receive(:update_grade_value).with(
          anything,
          hash_including(user_id: 100)
        )

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'when retrieving enrolled users fails' do
      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).and_return(nil)
      end

      it 'logs error about not being able to assign grade 0 to absent students' do
        expect(Resque.logger).to receive(:error).with(
          /Failed to retrieve enrolled users.*not be possible to assign grade 0/
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'still assigns max grade to present students' do
        expect(brightspace_client).to receive(:update_grade_value).with(
          anything,
          hash_including(user_id: 100, grade_value: Mconf::BrightspaceClient::MaxGrade)
        )
        expect(brightspace_client).to receive(:update_grade_value).with(
          anything,
          hash_including(user_id: 200, grade_value: Mconf::BrightspaceClient::MaxGrade)
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'reports attendance summary with zero absent students' do
        expect(Resque.logger).to receive(:info).with(
          /Attendance marking summary.*Total = 2.*Present.*success=2.*Absent.*success=0/
        )

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'when some grade updates fail' do
      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:get_course_users).and_return(enrolled_users_page1)
        
        # Student 100 succeeds, student 200 fails
        allow(brightspace_client).to receive(:update_grade_value)
          .with(anything, hash_including(user_id: 100)).and_return('success')
        allow(brightspace_client).to receive(:update_grade_value)
          .with(anything, hash_including(user_id: 200)).and_return(nil)
        allow(brightspace_client).to receive(:update_grade_value)
          .with(anything, hash_including(user_id: 300)).and_return('success')
      end

      it 'logs success for successful updates' do
        expect(Resque.logger).to receive(:info).with(
          /Successfully assigned max grade to student ID 100/
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'logs error for failed updates' do
        expect(Resque.logger).to receive(:error).with(
          /Failed to assign max grade to student ID 200/
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'reports attendance summary with failures' do
        expect(Resque.logger).to receive(:info).with(
          /Attendance marking summary.*Present.*success=1, failed=1.*Absent.*success=1, failed=0/
        )

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'with invalid JSON' do
      let(:invalid_json) { 'invalid json {' }

      it 'logs error and returns early' do
        expect(Resque.logger).to receive(:error).with(
          /Failed to parse JSON from meeting data/
        )

        described_class.perform_now(invalid_json, locale)
      end

      it 'does not attempt to call BrightspaceClient' do
        expect(Mconf::BrightspaceClient).not_to receive(:new)

        described_class.perform_now(invalid_json, locale)
      end
    end

    context 'when ScheduledMeeting is not found' do
      let(:conference_data_missing_meeting) do
        data = conference_data.dup
        data['data']['metadata']['bbb_meeting_db_id'] = '99999'
        data
      end

      it 'logs error and returns early' do
        expect(Resque.logger).to receive(:error).with(
          /Could not find ScheduledMeeting with ID 99999/
        )

        described_class.perform_now(conference_data_missing_meeting.to_json, locale)
      end
    end

    context 'when ScheduledMeeting ID is missing from metadata' do
      let(:conference_data_no_meeting_id) do
        data = conference_data.dup
        data['data']['metadata'].delete('bbb_meeting_db_id')
        data
      end

      it 'logs error and returns early' do
        expect(Resque.logger).to receive(:error).with(
          /Could not find 'bbb_meeting_db_id' in conference_data metadata/
        )

        described_class.perform_now(conference_data_no_meeting_id.to_json, locale)
      end
    end

    context 'when AppLaunch is not found' do
      let(:conference_data_missing_launch) do
        data = conference_data.dup
        data['data']['metadata']['bbb_launch_nonce'] = 'nonexistent_nonce'
        data
      end

      it 'logs error and returns early' do
        expect(Resque.logger).to receive(:error).with(
          /Could not find AppLaunch with nonce 'nonexistent_nonce'/
        )

        described_class.perform_now(conference_data_missing_launch.to_json, locale)
      end
    end

    context 'when AppLaunch nonce is missing from metadata' do
      let(:conference_data_no_launch_nonce) do
        data = conference_data.dup
        data['data']['metadata'].delete('bbb_launch_nonce')
        data
      end

      it 'logs error and returns early' do
        expect(Resque.logger).to receive(:error).with(
          /Could not find 'bbb_launch_nonce' in conference_data metadata/
        )

        described_class.perform_now(conference_data_no_launch_nonce.to_json, locale)
      end
    end

    context 'when conference attendees data is missing' do
      let(:conference_data_no_attendees) do
        data = conference_data.dup
        data['data'].delete('attendees')
        data
      end

      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
      end

      it 'logs error and returns early' do
        expect(Resque.logger).to receive(:error).with(
          /Conference attendees data is missing or not an array/
        )

        described_class.perform_now(conference_data_no_attendees.to_json, locale)
      end
    end

    context 'when start time has invalid format' do
      let(:conference_data_invalid_time) do
        data = conference_data.dup
        data['data']['start'] = 'invalid_time_format'
        data
      end

      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).and_return(enrolled_users_page1)
      end

      it 'logs warning and uses scheduled_meeting start date instead' do
        expect(Resque.logger).to receive(:warn).with(
          /Invalid start_time format.*Using scheduled_meeting start date/
        )

        described_class.perform_now(conference_data_invalid_time.to_json, locale)
      end

      it 'still creates grade object successfully' do
        expect(brightspace_client).to receive(:create_grade_object)

        described_class.perform_now(conference_data_invalid_time.to_json, locale)
      end
    end

    context 'with custom attendance category name from environment' do
      let(:custom_category_name) { 'Custom Attendance Category' }
      let(:custom_categories) do
        [{ 'Id' => 20, 'Name' => custom_category_name }]
      end

      before do
        allow(Mconf::Env).to receive(:fetch).with('BRIGHTSPACE_ATTENDANCE_CATEGORY_NAME', anything)
                                             .and_return(custom_category_name)
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(custom_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).and_return(enrolled_users_page1)
      end

      it 'uses the custom category name to find the category' do
        expect(Resque.logger).to receive(:info).with(
          /Grade category for attendances found, id=20/
        )

        described_class.perform_now(conference_data_json, locale)
      end

      it 'creates grade object with the found custom category' do
        expect(brightspace_client).to receive(:create_grade_object).with(
          course_id,
          20,
          anything
        )

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'with different locale' do
      let(:locale) { 'pt' }

      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).and_return(enrolled_users_page1)
      end

      it 'uses the specified locale for I18n translations' do
        expect(I18n).to receive(:with_locale).with('pt').and_call_original
        allow(I18n).to receive(:with_locale).and_call_original

        described_class.perform_now(conference_data_json, locale)
      end
    end

    context 'when attendee has no ext_user_id' do
      let(:conference_data_missing_user_id) do
        data = conference_data.dup
        data['data']['attendees'] = [
          { 'name' => 'Student Without ID' },
          { 'ext_user_id' => 'prefix_100', 'name' => 'Student 1' }
        ]
        data
      end

      before do
        allow(brightspace_client).to receive(:get_course_grade_categories).and_return(grade_categories)
        allow(brightspace_client).to receive(:create_grade_object).and_return(grade_object)
        allow(brightspace_client).to receive(:update_grade_value).and_return('success')
        allow(brightspace_client).to receive(:get_course_users).and_return(enrolled_users_page1)
      end

      it 'skips attendees without ext_user_id' do
        # Only student 100 should get a grade update
        expect(brightspace_client).to receive(:update_grade_value).with(
          anything,
          hash_including(user_id: 100, grade_value: Mconf::BrightspaceClient::MaxGrade)
        ).once

        described_class.perform_now(conference_data_missing_user_id.to_json, locale)
      end
    end
  end

  describe '#find_scheduled_meeting' do
    let(:job) { described_class.new }

    context 'with valid meeting ID' do
      it 'finds and returns the scheduled meeting' do
        result = job.send(:find_scheduled_meeting, conference_data)
        expect(result).to eq(scheduled_meeting)
      end
    end

    context 'when meeting ID is missing' do
      let(:data_no_meeting_id) do
        data = conference_data.dup
        data['data']['metadata'].delete('bbb_meeting_db_id')
        data
      end

      it 'returns nil and logs error' do
        expect(Resque.logger).to receive(:error).with(
          /Could not find 'bbb_meeting_db_id' in conference_data metadata/
        )

        result = job.send(:find_scheduled_meeting, data_no_meeting_id)
        expect(result).to be_nil
      end
    end

    context 'when meeting does not exist' do
      let(:data_invalid_meeting_id) do
        data = conference_data.dup
        data['data']['metadata']['bbb_meeting_db_id'] = '99999'
        data
      end

      it 'returns nil and logs error' do
        expect(Resque.logger).to receive(:error).with(
          /Could not find ScheduledMeeting with ID 99999/
        )

        result = job.send(:find_scheduled_meeting, data_invalid_meeting_id)
        expect(result).to be_nil
      end
    end
  end

  describe '#find_app_launch' do
    let(:job) { described_class.new }

    context 'with valid launch nonce' do
      it 'finds and returns the app launch' do
        result = job.send(:find_app_launch, conference_data)
        expect(result).to eq(app_launch)
      end
    end

    context 'when launch nonce is missing' do
      let(:data_no_nonce) do
        data = conference_data.dup
        data['data']['metadata'].delete('bbb_launch_nonce')
        data
      end

      it 'returns nil and logs error' do
        expect(Resque.logger).to receive(:error).with(
          /Could not find 'bbb_launch_nonce' in conference_data metadata/
        )

        result = job.send(:find_app_launch, data_no_nonce)
        expect(result).to be_nil
      end
    end

    context 'when app launch does not exist' do
      let(:data_invalid_nonce) do
        data = conference_data.dup
        data['data']['metadata']['bbb_launch_nonce'] = 'invalid_nonce'
        data
      end

      it 'returns nil and logs error' do
        expect(Resque.logger).to receive(:error).with(
          /Could not find AppLaunch with nonce 'invalid_nonce'/
        )

        result = job.send(:find_app_launch, data_invalid_nonce)
        expect(result).to be_nil
      end
    end
  end
end
