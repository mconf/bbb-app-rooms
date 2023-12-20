require 'rails_helper'

describe ErrorsController, type: :request do

  context "returns a not found response"  do
    before { get '/not_existing_page' }

    it { expect(response.status).to eq(404) }
    it { expect(response.status).not_to eq(500) }
  end

end
