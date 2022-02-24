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

end
