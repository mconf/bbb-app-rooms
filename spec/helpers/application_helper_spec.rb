require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
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

    it 'keeps them off a user without full permission' do
      allow(Abilities).to receive(:full_permission?).with(user).and_return(false)

      expect(helper.ai_documents_enabled?(user, room, Date.new(2026, 6, 12))).to be false
    end

    it 'keeps them off a consumer that does not allow them' do
      allow(helper).to receive(:ai_artifacts_enabled?).with(room).and_return(false)

      expect(helper.ai_documents_enabled?(user, room, Date.new(2026, 6, 12))).to be false
    end
  end
end
