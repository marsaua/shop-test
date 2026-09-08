require "rails_helper"

RSpec.describe "Cart", type: :request do
  describe "GET /cart" do
    it "requires sign in" do
      get cart_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the current user's running total" do
      user = create(:user)
      product = create(:product, price_cents: 1000)
      user.cart.cart_items.create!(product: product, quantity: 2)
      sign_in user

      get cart_path

      expect(response.body).to include("20.00")
    end
  end
end
