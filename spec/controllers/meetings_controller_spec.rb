# frozen_string_literal: true

require 'rails_helper'

describe MeetingsController, type: :controller do
  let(:room) { FactoryBot.create(:room) }
  let(:user) { User.new(uid: 'uid', full_name: 'Moderadora', roles: 'Instructor') }
  # BBB builds the internal id out of the external one, and the controller checks the
  # pair to keep a meeting of another room out
  let(:scheduled_meeting_id) { "#{room.meeting_id}-1" }
  let(:started_at) { Time.zone.now }
  let(:internal_meeting_id) do
    "#{Digest::SHA1.hexdigest(scheduled_meeting_id)}-#{(started_at.to_f * 1000).to_i}"
  end

  def base_params(extra = {})
    { room_id: room.handler, scheduled_meeting_id: scheduled_meeting_id,
      internal_id: internal_meeting_id }.merge(extra)
  end

  # What is under test is what the actions do with the suggestion, not how the launch
  # finds the room and the user
  before do
    allow(controller).to receive(:find_app_launch)
    allow(controller).to receive(:find_user) { controller.instance_variable_set(:@user, user) }
    allow(controller).to receive(:authorize_user!)
    allow(controller).to receive(:check_data_api_config)
    allow(controller.helpers).to receive(:ai_artifacts_enabled?).and_return(true)
    allow(controller).to receive(:update_meeting)
    allow(Mconf::DataApi).to receive(:get_meeting_naming_suggestions).and_return(nil)
  end

  describe '#resolve_ai_naming_suggestion' do
    it 'applies the title and the description to the meeting' do
      expect(controller).to receive(:update_meeting).with(
        room, internal_meeting_id,
        { 'meta_ai-naming-applied': true, name: 'Título sugerido', 'meta_description': 'Descrição sugerida' }
      )

      post :resolve_ai_naming_suggestion, params: base_params(
        decision: 'apply', title: 'Título sugerido', description: 'Descrição sugerida'
      )
    end

    it 'leaves the description of the meeting alone when the suggestion had none' do
      expect(controller).to receive(:update_meeting).with(
        room, internal_meeting_id, { 'meta_ai-naming-applied': true, name: 'Título sugerido' }
      )

      post :resolve_ai_naming_suggestion, params: base_params(decision: 'apply', title: 'Título sugerido')
    end

    # A blank title means the suggestion never loaded
    it 'writes nothing when the title is blank' do
      expect(controller).not_to receive(:update_meeting)

      post :resolve_ai_naming_suggestion, params: base_params(decision: 'apply', title: '')

      expect(flash[:error]).to eq(I18n.t('meetings.ai_naming_suggestion.error'))
    end

    it 'marks the suggestion as declined' do
      expect(controller).to receive(:update_meeting).with(
        room, internal_meeting_id, { 'meta_ai-naming-declined': true }
      )

      post :resolve_ai_naming_suggestion, params: base_params(decision: 'decline')
    end

    it 'writes nothing when the decision is not one of ours' do
      expect(controller).not_to receive(:update_meeting)

      post :resolve_ai_naming_suggestion, params: base_params(decision: 'whatever')

      expect(flash[:error]).to eq(I18n.t('meetings.ai_naming_suggestion.invalid_decision'))
    end

    it 'goes back to where the listing asked it to' do
      post :resolve_ai_naming_suggestion, params: base_params(decision: 'decline', redir_url: '/rooms/handler/meetings')

      expect(response).to redirect_to('/rooms/handler/meetings')
    end

    it 'ignores a redirect that leaves the app' do
      post :resolve_ai_naming_suggestion, params: base_params(decision: 'decline', redir_url: 'https://elsewhere.example.com')

      expect(response).to redirect_to(meetings_room_path(room))
    end

    # The browser reads the backslash as a slash, so this is '//elsewhere.example.com'
    it 'ignores a redirect that leaves the app through a backslash' do
      post :resolve_ai_naming_suggestion, params: base_params(decision: 'decline', redir_url: '/\\elsewhere.example.com')

      expect(response).to redirect_to(meetings_room_path(room))
    end

    it 'ignores a protocol relative redirect' do
      post :resolve_ai_naming_suggestion, params: base_params(decision: 'decline', redir_url: '//elsewhere.example.com')

      expect(response).to redirect_to(meetings_room_path(room))
    end

    it 'keeps the query string of the listing it goes back to' do
      post :resolve_ai_naming_suggestion, params: base_params(
        decision: 'decline', redir_url: '/rooms/handler/meetings?filter=recorded-only'
      )

      expect(response).to redirect_to('/rooms/handler/meetings?filter=recorded-only')
    end
  end

  describe 'a meeting of another room' do
    let(:other_room) { FactoryBot.create(:room) }
    let(:other_scheduled_meeting_id) { "#{other_room.meeting_id}-1" }
    let(:other_internal_meeting_id) do
      "#{Digest::SHA1.hexdigest(other_scheduled_meeting_id)}-#{(started_at.to_f * 1000).to_i}"
    end

    it 'is not renamed through a room the user moderates' do
      expect(controller).not_to receive(:update_meeting)

      post :resolve_ai_naming_suggestion, params: base_params(
        internal_id: other_internal_meeting_id, decision: 'apply', title: 'Título sugerido'
      )

      expect(response).to have_http_status(:not_found)
    end

    # The external id is the one the internal id is derived from, so passing both is the
    # way around a check made on the internal id alone
    it 'is not renamed when its own external id comes along' do
      expect(controller).not_to receive(:update_meeting)

      post :resolve_ai_naming_suggestion, params: base_params(
        scheduled_meeting_id: other_scheduled_meeting_id, internal_id: other_internal_meeting_id,
        decision: 'apply', title: 'Título sugerido'
      )

      expect(response).to have_http_status(:not_found)
    end

    it 'has no suggestion fetched for it' do
      expect(Mconf::DataApi).not_to receive(:get_meeting_naming_suggestions)

      get :ai_naming_suggestion_status, params: base_params(internal_id: other_internal_meeting_id)

      expect(response).to have_http_status(:not_found)
    end

    it 'has no artifacts requested for it' do
      expect(Mconf::LlmApi).not_to receive(:request_ai_artifacts)

      post :request_ai_artifacts, params: base_params(internal_id: other_internal_meeting_id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe '#ai_naming_suggestion' do
    it 'uses the suggestion the listing already had, without asking the Data API' do
      expect(Mconf::DataApi).not_to receive(:get_meeting_naming_suggestions)

      get :ai_naming_suggestion, params: base_params(
        suggested_title: 'Título sugerido', suggested_description: 'Descrição sugerida'
      )

      expect(response).to have_http_status(:ok)
    end

    it 'recovers the suggestion from the Data API and caches it on the meeting' do
      allow(Mconf::DataApi).to receive(:get_meeting_naming_suggestions)
        .and_return({ 'name' => 'Título sugerido', 'description' => 'Descrição sugerida' })

      expect(controller).to receive(:update_meeting).with(
        room, internal_meeting_id,
        { 'meta_ai-naming-suggested-title': 'Título sugerido',
          'meta_ai-naming-suggested-description': 'Descrição sugerida' }
      )

      get :ai_naming_suggestion, params: base_params
    end
  end

  describe '#ai_naming_suggestion_status' do
    it 'answers with the suggestion it found' do
      allow(Mconf::DataApi).to receive(:get_meeting_naming_suggestions)
        .and_return({ 'name' => 'Título sugerido', 'description' => 'Descrição sugerida' })

      get :ai_naming_suggestion_status, params: base_params

      expect(JSON.parse(response.body)).to eq(
        'suggestion_available' => true, 'title' => 'Título sugerido', 'description' => 'Descrição sugerida'
      )
    end

    # An empty answer is also what a meeting still generating its artifacts gets
    it 'keeps the flag when the Data API has nothing' do
      expect(controller).not_to receive(:update_meeting)

      get :ai_naming_suggestion_status, params: base_params

      expect(JSON.parse(response.body)['suggestion_available']).to be(false)
    end

    context 'when the meeting is long over' do
      let(:started_at) { 2.days.ago }

      it 'still keeps the flag, as the request for the artifacts may be recent' do
        expect(controller).not_to receive(:update_meeting)

        get :ai_naming_suggestion_status, params: base_params
      end
    end
  end
end
