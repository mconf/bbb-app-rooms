require 'rails_helper'

RSpec.describe ConsumerConfigServer, type: :model do

  it "creates a new instance given valid attributes" do
    expect(FactoryBot.build(:consumer_config_server)).to be_valid
  end

  it { should belong_to(:consumer_config) }

end
