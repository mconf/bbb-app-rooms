require 'rails_helper'
require 'spec_helper'

RSpec.describe Room, type: :model do

  it "creates a new instance given valid attributes" do
    expect(FactoryBot.build(:room)).to be_valid
  end

end
