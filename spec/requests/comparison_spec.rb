require "rails_helper"

RSpec.describe "Comparison", type: :request do
  describe "GET /comparison" do
    it "is visible to guests" do
      get comparison_path
      expect(response).to have_http_status(:ok)
    end

    it "is visible to signed-in users" do
      sign_in create(:user)
      get comparison_path
      expect(response).to have_http_status(:ok)
    end
  end
end
