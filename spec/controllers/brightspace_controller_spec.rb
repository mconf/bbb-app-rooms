require 'rails_helper'

describe BrightspaceController, type: :controller do
  let(:room) { FactoryBot.create(:room) }
  let(:scheduled_meeting) do
    FactoryBot.create(:scheduled_meeting,
                      room: room,
                      name: 'Test Meeting',
                      start_at: Time.zone.now)
  end

  let(:consumer_config) { FactoryBot.create(:consumer_config, key: 'test_consumer_key') }
  let(:brightspace_oauth) do
    FactoryBot.create(:consumer_config_brightspace_oauth,
                      consumer_config: consumer_config,
                      url: 'https://example.brightspace.com')
  end

  let(:app_launch) do
    launch = FactoryBot.create(:app_launch, nonce: 'test_nonce')
    launch.params = {
      'user_id' => 'brightspace_user_123',
      'lis_person_name_full' => 'Test User',
      'lis_person_contact_email_primary' => 'test@example.com',
      'roles' => 'Instructor',
      'context_id' => '12345',
      'custom_params' => {
        'oauth_consumer_key' => consumer_config.key
      }
    }
    launch.omniauth_auth = {
      'brightspace' => {
        'credentials' => {
          'token' => 'test_access_token'
        }
      }
    }
    launch.save!
    launch
  end

  let(:user) do
    User.new(
      uid: 'brightspace_user_123',
      full_name: 'Test User',
      email: 'test@example.com',
      roles: 'Instructor',
      launch_nonce: app_launch.nonce
    )
  end

  let(:brightspace_client) { instance_double(Mconf::BrightspaceClient) }

  before do
    # Ensure brightspace_oauth is created before tests
    brightspace_oauth

    # Mock controller methods
    allow(controller).to receive(:find_room).and_return(room)
    allow(controller).to receive(:validate_room).and_return(true)
    allow(controller).to receive(:find_user).and_return(user)
    allow(controller).to receive(:find_scheduled_meeting).and_return(scheduled_meeting)
    allow(controller).to receive(:validate_scheduled_meeting).and_return(true)
    allow(controller).to receive(:authorize_user!).and_return(true)
    allow(controller).to receive(:find_app_launch).and_return(app_launch)
    allow(controller).to receive(:authenticate_with_oauth!).and_return(true)

    # Set instance variables that before_action filters would set
    controller.instance_variable_set(:@room, room)
    controller.instance_variable_set(:@scheduled_meeting, scheduled_meeting)
    controller.instance_variable_set(:@user, user)
    controller.instance_variable_set(:@app_launch, app_launch)
  end

  describe 'GET #fetch_profile_image' do
    let(:profile_image_data) { 'binary_image_data' }
    let(:file_name) { "#{consumer_config.key}/brightspace_user_123.jpg" }

    before do
      allow(Mconf::BrightspaceClient).to receive(:new).and_return(brightspace_client)
      allow(brightspace_client).to receive(:get_profile_image).and_return(profile_image_data)
      allow(Mconf::S3Client).to receive(:upload_public_file).and_return(true)
      allow(Mconf::S3Client).to receive(:public_url_for).and_return("https://s3.example.com/#{file_name}")
    end

    it 'initializes BrightspaceClient with correct parameters' do
      expect(Mconf::BrightspaceClient).to receive(:new).with(
        'https://example.brightspace.com',
        'test_access_token',
        hash_including(user_info: { email: user.email, launch_nonce: app_launch.nonce })
      )

      get :fetch_profile_image, params: { room_id: room.id }
    end

    it 'fetches the profile image' do
      expect(brightspace_client).to receive(:get_profile_image)

      get :fetch_profile_image, params: { room_id: room.id }
    end

    context 'when profile image is retrieved successfully' do
      it 'uploads the image to S3' do
        expect(Mconf::S3Client).to receive(:upload_public_file).with(profile_image_data, file_name)

        get :fetch_profile_image, params: { room_id: room.id }
      end

      it 'updates the app_launch with the profile image URL' do
        expect(app_launch).to receive(:set_param).with('profile_image_url', "https://s3.example.com/#{file_name}")

        get :fetch_profile_image, params: { room_id: room.id }
      end

      it 'redirects to the room path' do
        get :fetch_profile_image, params: { room_id: room.id }

        expect(response).to redirect_to(room_path(room))
      end
    end

    context 'when profile image is not found' do
      before do
        allow(brightspace_client).to receive(:get_profile_image).and_return(nil)
      end

      it 'does not upload to S3' do
        expect(Mconf::S3Client).not_to receive(:upload_public_file)

        get :fetch_profile_image, params: { room_id: room.id }
      end

      it 'does not update the app_launch' do
        expect(app_launch).not_to receive(:set_param)

        get :fetch_profile_image, params: { room_id: room.id }
      end

      it 'still redirects to the room path' do
        get :fetch_profile_image, params: { room_id: room.id }

        expect(response).to redirect_to(room_path(room))
      end
    end

    context 'when S3 upload fails' do
      before do
        allow(Mconf::S3Client).to receive(:upload_public_file).and_return(false)
      end

      it 'does not update the app_launch' do
        expect(app_launch).not_to receive(:set_param)

        get :fetch_profile_image, params: { room_id: room.id }
      end

      it 'redirects to the room path' do
        get :fetch_profile_image, params: { room_id: room.id }

        expect(response).to redirect_to(room_path(room))
      end
    end
  end

  describe 'POST #send_create_calendar_event' do
    let(:event_data) do
      {
        event_id: 123456,
        lti_link_id: 789012
      }
    end

    before do
      allow(controller).to receive(:prevent_event_duplication)
      allow(controller).to receive(:send_calendar_event).and_return(event_data)
      allow(controller).to receive(:pop_redirect_from_session!)
        .with('brightspace_return_to')
        .and_return([room_path(room)])
      session[:brightspace_return_to] = room_path(room)
    end

    it 'calls send_calendar_event with correct parameters' do
      expect(controller).to receive(:send_calendar_event).with(
        :create,
        app_launch,
        hash_including(scheduled_meeting: scheduled_meeting)
      )

      post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
    end

    it 'creates a BrightspaceCalendarEvent record' do
      expect {
        post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
      }.to change(BrightspaceCalendarEvent, :count).by(1)
    end

    it 'creates BrightspaceCalendarEvent with correct attributes' do
      post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

      calendar_event = BrightspaceCalendarEvent.last
      expect(calendar_event.event_id).to eq(123456)
      expect(calendar_event.link_id).to eq(789012)
      expect(calendar_event.scheduled_meeting_hash_id).to eq(scheduled_meeting.hash_id)
      expect(calendar_event.room_id).to eq(room.id)
    end

    it 'redirects to the stored return path' do
      post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

      expect(response).to redirect_to(room_path(room))
    end

    context 'when BrightspaceCalendarEvent already exists' do
      let!(:existing_event) do
        BrightspaceCalendarEvent.create!(
          event_id: 999999,
          link_id: 888888,
          scheduled_meeting_hash_id: scheduled_meeting.hash_id,
          room_id: room.id
        )
      end

      it 'does not create a duplicate record' do
        expect {
          post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
        }.not_to change(BrightspaceCalendarEvent, :count)
      end
    end

    context 'when send_calendar_event raises an error' do
      before do
        allow(controller).to receive(:send_calendar_event)
          .and_raise(BrightspaceHelper::SendCalendarEventError, 'API Error')
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/Failed to receive send_create_calendar_event data/)

        post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
      end

      it 'does not create a BrightspaceCalendarEvent record' do
        expect {
          post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
        }.not_to change(BrightspaceCalendarEvent, :count)
      end

      it 'still redirects to the return path' do
        post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

        expect(response).to redirect_to(room_path(room))
      end
    end
  end

  describe 'POST #send_update_calendar_event' do
    let(:event_data) do
      {
        event_id: 123456,
        lti_link_id: 789012
      }
    end

    let!(:existing_event) do
      BrightspaceCalendarEvent.create!(
        event_id: 999999,
        link_id: 888888,
        scheduled_meeting_hash_id: scheduled_meeting.hash_id,
        room_id: room.id
      )
    end

    before do
      allow(controller).to receive(:send_calendar_event).and_return(event_data)
      allow(controller).to receive(:pop_redirect_from_session!)
        .with('brightspace_return_to')
        .and_return([room_path(room)])
      session[:brightspace_return_to] = room_path(room)
    end

    it 'calls send_calendar_event with correct parameters' do
      expect(controller).to receive(:send_calendar_event).with(
        :update,
        app_launch,
        hash_including(scheduled_meeting: scheduled_meeting)
      )

      post :send_update_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
    end

    it 'updates the existing BrightspaceCalendarEvent record' do
      post :send_update_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

      existing_event.reload
      expect(existing_event.event_id).to eq(123456)
      expect(existing_event.link_id).to eq(789012)
    end

    it 'does not create a new record' do
      expect {
        post :send_update_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
      }.not_to change(BrightspaceCalendarEvent, :count)
    end

    it 'redirects to the stored return path' do
      post :send_update_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

      expect(response).to redirect_to(room_path(room))
    end

    context 'when BrightspaceCalendarEvent does not exist' do
      before do
        existing_event.destroy
      end

      it 'creates a new record' do
        expect {
          post :send_update_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
        }.to change(BrightspaceCalendarEvent, :count).by(1)
      end
    end

    context 'when send_calendar_event raises an error' do
      before do
        allow(controller).to receive(:send_calendar_event)
          .and_raise(BrightspaceHelper::SendCalendarEventError, 'API Error')
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/Failed to receive send_update_calendar_event data/)

        post :send_update_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
      end

      it 'does not update the record' do
        original_event_id = existing_event.event_id

        post :send_update_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

        existing_event.reload
        expect(existing_event.event_id).to eq(original_event_id)
      end

      it 'still redirects to the return path' do
        post :send_update_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

        expect(response).to redirect_to(room_path(room))
      end
    end
  end

  describe 'POST #send_delete_calendar_event' do
    let!(:existing_event) do
      BrightspaceCalendarEvent.create!(
        event_id: 123456,
        link_id: 789012,
        scheduled_meeting_hash_id: scheduled_meeting.hash_id,
        room_id: room.id
      )
    end

    before do
      allow(controller).to receive(:send_calendar_event)
      allow(controller).to receive(:pop_redirect_from_session!)
        .with('brightspace_return_to')
        .and_return([room_path(room)])
      allow(controller).to receive(:find_scheduled_meeting) # skip this before_action for delete
      allow(controller).to receive(:validate_scheduled_meeting) # skip this before_action for delete
      session[:brightspace_return_to] = room_path(room)
    end

    it 'calls send_calendar_event with correct parameters' do
      expect(controller).to receive(:send_calendar_event).with(
        :delete,
        app_launch,
        hash_including(
          scheduled_meeting_hash_id: scheduled_meeting.hash_id,
          room: room
        )
      )

      post :send_delete_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
    end

    it 'deletes the BrightspaceCalendarEvent record' do
      expect {
        post :send_delete_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
      }.to change(BrightspaceCalendarEvent, :count).by(-1)
    end

    it 'redirects to the stored return path' do
      post :send_delete_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

      expect(response).to redirect_to(room_path(room))
    end

    context 'when BrightspaceCalendarEvent does not exist' do
      before do
        existing_event.destroy
      end

      it 'does not raise an error' do
        expect {
          post :send_delete_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
        }.not_to raise_error
      end

      it 'still redirects to the return path' do
        post :send_delete_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

        expect(response).to redirect_to(room_path(room))
      end
    end

    context 'when send_calendar_event raises an error' do
      before do
        allow(controller).to receive(:send_calendar_event)
          .and_raise(BrightspaceHelper::SendCalendarEventError, 'API Error')
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/Failed to send delete calendar event/)

        post :send_delete_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
      end

      it 'does not delete the record' do
        expect {
          post :send_delete_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
        }.not_to change(BrightspaceCalendarEvent, :count)
      end

      it 'still redirects to the return path' do
        post :send_delete_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

        expect(response).to redirect_to(room_path(room))
      end
    end
  end

  describe '#prevent_event_duplication' do
    before do
      allow(controller).to receive(:send_calendar_event)
      allow(controller).to receive(:pop_redirect_from_session!)
        .with('brightspace_return_to')
        .and_return([room_path(room)])
      session[:brightspace_return_to] = room_path(room)
    end

    context 'when calendar event already exists' do
      let!(:existing_event) do
        BrightspaceCalendarEvent.create!(
          event_id: 123456,
          link_id: 789012,
          scheduled_meeting_hash_id: scheduled_meeting.hash_id,
          room_id: room.id
        )
      end

      before do
        # Re-enable the before_action for this test
        allow(controller).to receive(:prevent_event_duplication).and_call_original
      end

      it 'redirects to the room page' do
        post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }

        expect(response).to redirect_to(room)
      end

      it 'does not call send_calendar_event' do
        expect(controller).not_to receive(:send_calendar_event)

        post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
      end

      it 'logs an info message' do
        allow(Rails.logger).to receive(:info).and_call_original
        expect(Rails.logger).to receive(:info).with('Brightspace calendar event already sent.')

        post :send_create_calendar_event, params: { room_id: room.id, id: scheduled_meeting.hash_id }
      end
    end
  end

  describe '#set_event' do
    it 'sets @custom_params with permitted params' do
      allow(controller).to receive(:send_calendar_event).and_return({ event_id: 123, lti_link_id: 456 })
      allow(controller).to receive(:pop_redirect_from_session!).and_return([room_path(room)])

      post :send_create_calendar_event, params: {
        room_id: room.id,
        id: scheduled_meeting.hash_id,
        app_id: 'test_app',
        event_id: 'event_123',
        session_set: 'should_be_deleted'
      }

      custom_params = controller.instance_variable_get(:@custom_params)
      expect(custom_params['launch_nonce']).to eq(app_launch.nonce)
      expect(custom_params['event']).to eq('send_create_calendar_event')
      expect(custom_params['app_id']).to eq('test_app')
      expect(custom_params['event_id']).to eq('event_123')
      expect(custom_params).not_to have_key('session_set')
    end
  end
end
