require "rails_helper"

RSpec.describe "Application layout", type: :request do
  it "renders the shared header and footer around every page" do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Shop Trololo")
    expect(response.body).to include("simulated")
  end
end
