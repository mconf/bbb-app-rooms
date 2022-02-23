require 'rails_helper'
require 'spec_helper'

RSpec.describe AppLaunch, type: :model do

  it "creates a new instance given valid attributes" do
    expect(FactoryBot.build(:app_launch)).to be_valid
  end

end
