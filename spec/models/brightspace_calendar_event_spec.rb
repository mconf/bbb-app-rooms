require 'rails_helper'

RSpec.describe BrightspaceCalendarEvent, type: :model do

  context "creates a new instance" do
    let(:room) { FactoryBot.create(:room) }
    let(:meeting) { FactoryBot.create(:scheduled_meeting, room: room) }
    let(:calendar_event) {
      FactoryBot.build(
        :brightspace_calendar_event,
        scheduled_meeting: meeting,
        room_id: meeting.room_id,
      )
    }

    it "given valid attributes" do
      expect(calendar_event).to be_valid
    end

    it "given invalid attributes" do
      expect(FactoryBot.build(:brightspace_calendar_event, scheduled_meeting: nil)).not_to be_valid
    end
  end

end
