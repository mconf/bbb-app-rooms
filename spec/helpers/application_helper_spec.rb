require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#session_documents_generating?' do
    let(:window) { ApplicationHelper::SESSION_DOCUMENTS_GENERATING_WINDOW }

    # The API gives the timestamps of meetings in milliseconds
    def ms(time)
      (time.to_f * 1000).to_i
    end

    it 'presumes the documents are coming right after the meeting ends' do
      expect(helper.session_documents_generating?(ms(1.minute.ago))).to be true
    end

    it 'still presumes it just before the window closes' do
      expect(helper.session_documents_generating?(ms((window - 1.minute).ago))).to be true
    end

    it 'gives up once the window has passed' do
      expect(helper.session_documents_generating?(ms((window + 1.minute).ago))).to be false
    end

    it 'gives up on a meeting from another day' do
      expect(helper.session_documents_generating?(ms(2.days.ago))).to be false
    end

    it 'presumes nothing while the meeting is still running' do
      expect(helper.session_documents_generating?(ms(1.minute.ago), 'true')).to be false
    end

    it 'presumes nothing without an end time' do
      expect(helper.session_documents_generating?(nil)).to be false
      expect(helper.session_documents_generating?('')).to be false
    end

    it 'reads a timestamp in seconds too' do
      expect(helper.session_documents_generating?(1.minute.ago.to_i)).to be true
      expect(helper.session_documents_generating?(2.days.ago.to_i)).to be false
    end
  end

  describe '#internal_meeting_date' do
    it 'reads the date from the timestamp the id ends with' do
      expect(helper.internal_meeting_date('abc123-1786727361386'))
        .to eq(Time.at(1786727361.386).to_date)
    end

    it 'has no date for an id that does not end with one' do
      expect(helper.internal_meeting_date('abc123')).to be_nil
      expect(helper.internal_meeting_date('abc123-notatimestamp')).to be_nil
      expect(helper.internal_meeting_date(nil)).to be_nil
    end
  end

  describe '#ai_documents_enabled?' do
    let(:user) { double('user') }
    let(:room) { double('room') }

    before do
      allow(Abilities).to receive(:full_permission?).with(user).and_return(true)
      allow(helper).to receive(:ai_artifacts_enabled?).with(room).and_return(true)
      allow(Rails.configuration).to receive(:ai_artifacts_release_date).and_return(Date.new(2026, 6, 11))
    end

    it 'offers the documents of a meeting held after the release' do
      expect(helper.ai_documents_enabled?(user, room, Date.new(2026, 6, 12))).to be true
    end

    it 'offers them on the day of the release' do
      expect(helper.ai_documents_enabled?(user, room, Date.new(2026, 6, 11))).to be true
    end

    it 'keeps them off a meeting held before the release' do
      expect(helper.ai_documents_enabled?(user, room, Date.new(2026, 6, 10))).to be false
    end

    it 'keeps them off a meeting whose date is unknown' do
      expect(helper.ai_documents_enabled?(user, room, nil)).to be false
    end

    it 'offers them for any date when no release date is set' do
      allow(Rails.configuration).to receive(:ai_artifacts_release_date).and_return(nil)

      expect(helper.ai_documents_enabled?(user, room, Date.new(2020, 1, 1))).to be true
      expect(helper.ai_documents_enabled?(user, room, nil)).to be true
    end

    # the config falls back to an empty string, not to nil, when the env is not set
    it 'offers them for any date when the release date is empty' do
      allow(Rails.configuration).to receive(:ai_artifacts_release_date).and_return('')

      expect(helper.ai_documents_enabled?(user, room, Date.new(2020, 1, 1))).to be true
      expect(helper.ai_documents_enabled?(user, room, nil)).to be true
    end

    it 'keeps them off a user without full permission' do
      allow(Abilities).to receive(:full_permission?).with(user).and_return(false)

      expect(helper.ai_documents_enabled?(user, room, Date.new(2026, 6, 12))).to be false
    end

    it 'keeps them off a consumer that does not allow them' do
      allow(helper).to receive(:ai_artifacts_enabled?).with(room).and_return(false)

      expect(helper.ai_documents_enabled?(user, room, Date.new(2026, 6, 12))).to be false
    end
  end

  describe '#ai_naming_suggestion_offered?' do
    let(:user) { double('user') }
    let(:room) { double('room') }

    def meeting(metadata = {})
      { internalMeetingID: 'abc123-1786727361386', metadata: metadata }
    end

    before do
      allow(helper).to receive(:ai_documents_enabled?).and_return(true)
    end

    it 'offers the suggestion a meeting already carries' do
      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({ 'ai-naming-suggested-title': 'Título' })))
        .to be true
    end

    # The icon shows while the suggestion is still being generated
    it 'offers it to a meeting that asked for its artifacts' do
      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({ 'ai-artifacts-requested': 1.minute.ago.utc.iso8601 })))
        .to be true
    end

    # The callback that would clear the mark can be lost, and without a deadline the
    # listing would ask the Data API about this meeting on every load, forever
    it 'gives up waiting once no callback could arrive any more' do
      past = (Rails.application.config.llm_artifact_cache_ttl + 60).seconds.ago

      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({ 'ai-artifacts-requested': past.utc.iso8601 })))
        .to be false
    end

    it 'waits until the last moment before that' do
      recent = (Rails.application.config.llm_artifact_cache_ttl - 60).seconds.ago

      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({ 'ai-artifacts-requested': recent.utc.iso8601 })))
        .to be true
    end

    # Giving up on the wait says nothing about a suggestion that did arrive
    it 'keeps offering a suggestion it already has, however old the request' do
      past = (Rails.application.config.llm_artifact_cache_ttl + 60).seconds.ago

      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({
        'ai-naming-suggested-title': 'Título', 'ai-artifacts-requested': past.utc.iso8601
      }))).to be true
    end

    it 'offers nothing for a mark it cannot read' do
      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({ 'ai-artifacts-requested': 'true' })))
        .to be false
      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({ 'ai-artifacts-requested': '' })))
        .to be false
      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({ 'ai-artifacts-requested': {} })))
        .to be false
    end

    it 'offers nothing to a meeting that never asked for them' do
      expect(helper.ai_naming_suggestion_offered?(user, room, meeting)).to be false
    end

    it 'offers nothing once the suggestion was applied' do
      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({
        'ai-naming-suggested-title': 'Título', 'ai-naming-applied': 'true'
      }))).to be false
    end

    it 'offers nothing once the suggestion was declined' do
      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({
        'ai-naming-suggested-title': 'Título', 'ai-naming-declined': 'true'
      }))).to be false
    end

    it 'offers nothing when the AI documents are off' do
      allow(helper).to receive(:ai_documents_enabled?).and_return(false)

      expect(helper.ai_naming_suggestion_offered?(user, room, meeting({ 'ai-naming-suggested-title': 'Título' })))
        .to be false
    end

    # The date of the meeting is what says whether it is past the release
    it 'takes the date of the meeting from its internal id' do
      expect(helper).to receive(:ai_documents_enabled?)
        .with(user, room, Time.at(1786727361.386).to_date).and_return(true)

      helper.ai_naming_suggestion_offered?(user, room, meeting({ 'ai-artifacts-requested': 1.minute.ago.utc.iso8601 }))
    end
  end

  describe '#ai_naming_suggestion_cached?' do
    it 'finds the title the callback stored' do
      expect(helper.ai_naming_suggestion_cached?({ metadata: { 'ai-naming-suggested-title': 'Título' } }))
        .to be true
    end

    it 'finds none on a meeting without one' do
      expect(helper.ai_naming_suggestion_cached?({ metadata: {} })).to be false
      expect(helper.ai_naming_suggestion_cached?({})).to be false
    end

    # The API answers an empty metadata with an empty hash, not with an empty string
    it 'takes an empty metadata for no title' do
      expect(helper.ai_naming_suggestion_cached?({ metadata: { 'ai-naming-suggested-title': {} } }))
        .to be false
    end
  end

  describe '#meeting_description' do
    let(:recording) { { metadata: { 'bbb-recording-description': 'Descrição agendada' } } }

    it 'shows the description the suggestion applied' do
      meeting = { metadata: { description: 'Descrição da IA' } }

      expect(helper.meeting_description(meeting, recording)).to eq('Descrição da IA')
    end

    it 'falls back to the one the meeting was scheduled with' do
      expect(helper.meeting_description({ metadata: {} }, recording)).to eq('Descrição agendada')
    end

    it 'has nothing to show without either of them' do
      expect(helper.meeting_description({ metadata: {} }, { metadata: {} })).to be_nil
      expect(helper.meeting_description({ metadata: {} })).to be_nil
    end

    it 'falls back when the applied description is empty' do
      meeting = { metadata: { description: {} } }

      expect(helper.meeting_description(meeting, recording)).to eq('Descrição agendada')
    end
  end

  describe '#metadata_text' do
    it 'takes the text of a metadata that has one' do
      expect(helper.metadata_text('Título')).to eq('Título')
    end

    # The API answers an empty metadata with an empty hash, not with an empty string
    it 'takes anything that is not a string for no text' do
      expect(helper.metadata_text({})).to be_nil
      expect(helper.metadata_text(nil)).to be_nil
      expect(helper.metadata_text('')).to be_nil
    end
  end
end
