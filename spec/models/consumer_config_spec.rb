require 'rails_helper'
require "spec_helper"

RSpec.describe ConsumerConfig, type: :model do

  it "creates a new instance given valid attributes" do
    expect(FactoryBot.build(:consumer_config)).to be_valid
  end

  it { is_expected.to validate_uniqueness_of(:key) }

end
