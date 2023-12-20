require 'rails_helper'

RSpec.describe ConsumerConfigBrightspaceOauth, type: :model do

  it "creates a new instance given valid attributes" do
    expect(FactoryBot.build(:consumer_config_brightspace_oauth)).to be_valid
  end

end
