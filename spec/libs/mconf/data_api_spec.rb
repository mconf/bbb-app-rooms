require 'rails_helper'

RSpec.describe Mconf::DataApi do
  let(:guid) { 'institution-guid' }
  let(:internal_meeting_id) { 'abc123-1750000000000' }

  describe '.get_meeting_documents' do
    before do
      allow(Rails.application.config).to receive(:data_api_url).and_return('https://data-api.example.com')
      allow(described_class).to receive(:get_engagement_report).and_return(nil)
    end

    def stub_objects(objects)
      allow(described_class).to receive(:list_objects).and_return(objects)
    end

    it 'returns nil when the guid is missing' do
      expect(described_class.get_meeting_documents('', internal_meeting_id)).to be_nil
    end

    it 'groups the documents by what they were made from' do
      stub_objects([
        { 'file_name' => 'activities.txt', 'link' => 'https://files/activities' },
        { 'file_name' => 'notes.txt', 'link' => 'https://files/notes' },
        { 'file_name' => 'summary.txt', 'link' => 'https://files/recording-summary' },
        { 'file_name' => 'transcription.txt', 'link' => 'https://files/recording-transcription' },
        { 'file_name' => 'no_record/summary.txt', 'link' => 'https://files/session-summary' },
        { 'file_name' => 'no_record/transcription.txt', 'link' => 'https://files/session-transcription' }
      ])

      documents = described_class.get_meeting_documents(guid, internal_meeting_id)

      expect(documents['meeting']).to eq(
        'participants_list' => 'https://files/activities',
        'shared_notes' => 'https://files/notes'
      )
      expect(documents['recording']).to eq(
        'ai_summary' => 'https://files/recording-summary',
        'transcription' => 'https://files/recording-transcription'
      )
      expect(documents['session']).to eq(
        'ai_summary' => 'https://files/session-summary',
        'transcription' => 'https://files/session-transcription'
      )
      expect(documents['has_session_objects']).to be true
    end

    it 'keeps the groups apart when the meeting was not recorded' do
      stub_objects([
        { 'file_name' => 'no_record/summary.txt', 'link' => 'https://files/session-summary' }
      ])

      documents = described_class.get_meeting_documents(guid, internal_meeting_id)

      expect(documents['session']).to eq('ai_summary' => 'https://files/session-summary')
      expect(documents['recording']).to be_empty
    end

    it 'ignores files that are not documents shown to the user' do
      stub_objects([
        { 'file_name' => 'video.mp4', 'link' => 'https://files/video' },
        { 'file_name' => 'no_record/whatever.txt', 'link' => 'https://files/whatever' },
        { 'file_name' => '', 'link' => 'https://files/nameless' }
      ])

      documents = described_class.get_meeting_documents(guid, internal_meeting_id)

      expect(documents['meeting']).to be_empty
      expect(documents['session']).to be_empty
      expect(documents['recording']).to be_empty
    end

    it 'returns every group empty when there are no objects' do
      stub_objects(nil)

      expect(described_class.get_meeting_documents(guid, internal_meeting_id))
        .to eq('meeting' => {}, 'session' => {}, 'recording' => {}, 'has_session_objects' => false)
    end

    it 'reports the objects of the session even when none of them is a document yet' do
      stub_objects([
        { 'file_name' => 'no_record/audio.ogg', 'link' => 'https://files/session-audio' }
      ])

      documents = described_class.get_meeting_documents(guid, internal_meeting_id)

      expect(documents['has_session_objects']).to be true
      expect(documents['session']).to be_empty
    end

    it 'reports no objects of the session when nothing is stored under its prefix' do
      stub_objects([
        { 'file_name' => 'summary.txt', 'link' => 'https://files/recording-summary' }
      ])

      expect(described_class.get_meeting_documents(guid, internal_meeting_id)['has_session_objects']).to be false
    end

    it 'adds the engagement report to the documents of the meeting' do
      stub_objects([])
      allow(described_class).to receive(:get_engagement_report).and_return('https://files/engagement')

      documents = described_class.get_meeting_documents(guid, internal_meeting_id)

      expect(documents['meeting']).to eq('engagement_report' => 'https://files/engagement')
    end
  end
end
