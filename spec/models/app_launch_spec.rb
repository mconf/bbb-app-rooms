require 'rails_helper'
require 'spec_helper'

RSpec.describe AppLaunch, type: :model do

  it "creates a new instance given valid attributes" do
    expect(FactoryBot.build(:app_launch)).to be_valid
  end

  describe '#coc_launch?' do
    context "when the custom_params's tag equals 'coc'" do
      subject { FactoryBot.create(:app_launch, params: { custom_params: { tag: 'coc' } }) }
      it { expect(subject.coc_launch?).to eql(true) }
    end

    context "when the custom_params's tag doesn't equals 'coc'" do
      subject { FactoryBot.create(:app_launch, params: { custom_params: { tag: 'something' } }) }
      it { expect(subject.coc_launch?).to eql(false) }
    end

    context "when the custom_params don't include a tag" do
      subject { FactoryBot.create(:app_launch, params: { custom_params: {} }) }
      it { expect(subject.coc_launch?).to eql(false) }
    end
  end
end
