require 'rails_helper'

describe HealthCheckController, type: :request do

  describe "GET /health_check#all" do
    it "return 200 status" do
      get "/health_check"
      expect(response.status).to eq 200
    end
  end

end
