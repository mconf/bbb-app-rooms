require 'rails_helper'

describe WebhooksController, type: :controller do
  describe '#ai_artifacts' do
    let(:room) { FactoryBot.create(:room) }
    let(:internal_meeting_id) { 'internal-meeting-id-from-the-cache' }
    let(:task_id) { 'task-abc-123' }
    let(:cached_context) do
      { room_handler: room.handler,
        internal_meeting_id: internal_meeting_id,
        requested_artifact_types: ['ai_summary'] }
    end
    let(:callback_body) do
      { task_id: task_id,
        meeting_id: internal_meeting_id,
        summary_status: 'success',
        transcription_status: 'success',
        suggested_name: 'Título sugerido',
        suggested_description: 'Descrição sugerida' }
    end
    let(:expected_metadata) do
      { 'meta_ai-naming-suggested-title': 'Título sugerido',
        'meta_ai-naming-suggested-description': 'Descrição sugerida' }
    end

    # The cache is a null store in the test environment, so what the callback finds there
    # is stubbed instead of written
    before do
      allow(Rails.cache).to receive(:read).and_return(nil)
      allow(Rails.cache).to receive(:read).with("llm_callback_#{task_id}").and_return(cached_context)
      allow(controller).to receive(:update_meeting)
    end

    def post_callback(body)
      post :ai_artifacts, body: body.to_json, as: :json
    end

    it 'stores the suggestion on the metadata of the meeting' do
      expect(controller).to receive(:update_meeting).with(room, internal_meeting_id, expected_metadata)

      post_callback(callback_body)

      expect(response).to have_http_status(:ok)
    end

    # This endpoint has no authentication: a forged POST must not be able to write
    # metadata onto a meeting of its choosing
    it 'writes on the meeting it cached, not on the one the request names' do
      expect(controller).to receive(:update_meeting).with(room, internal_meeting_id, expected_metadata)

      post_callback(callback_body.merge(meeting_id: 'a-meeting-of-someone-else'))
    end

    it 'answers with not found and writes nothing when the task_id is unknown' do
      expect(controller).not_to receive(:update_meeting)

      post_callback(callback_body.merge(task_id: 'a-task-nobody-asked-for'))

      expect(response).to have_http_status(:not_found)
    end

    # A suggestion always comes with a successful summary, so a callback without one
    # settles it: there will never be a suggestion, and the listing can stop asking the
    # Data API about this meeting
    it 'clears the request flag when there is no suggestion' do
      expect(controller).to receive(:update_meeting)
        .with(room, internal_meeting_id, { 'meta_ai-artifacts-requested': '' })

      post_callback(callback_body.except(:suggested_name, :suggested_description))

      expect(response).to have_http_status(:ok)
    end

    it "doesn't touch the request flag when a suggestion did come" do
      expect(controller).to receive(:update_meeting) do |_room, _id, meta|
        expect(meta).not_to have_key(:'meta_ai-artifacts-requested')
      end

      post_callback(callback_body)
    end

    context 'when the room of the meeting is gone' do
      let(:cached_context) do
        { room_handler: 'a-handler-of-a-room-that-no-longer-exists',
          internal_meeting_id: internal_meeting_id,
          requested_artifact_types: ['ai_summary'] }
      end

      it 'logs the error and carries on with the callback' do
        allow(Rails.logger).to receive(:error)
        expect(controller).not_to receive(:update_meeting)

        post_callback(callback_body)

        expect(Rails.logger).to have_received(:error).with(
          "[WebhooksController#persist_naming_suggestion] Room not found for " \
          "handler='a-handler-of-a-room-that-no-longer-exists'"
        )
        expect(response).to have_http_status(:ok)
      end
    end

    # Failing to store a suggestion is not a reason to fail the callback the artifacts
    # themselves depend on
    it 'carries on with the callback when the API fails' do
      allow(controller).to receive(:update_meeting).and_raise(StandardError, 'boom')

      post_callback(callback_body)

      expect(response).to have_http_status(:ok)
    end
  end
end
