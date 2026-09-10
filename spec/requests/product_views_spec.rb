require "rails_helper"

RSpec.describe "Product views", type: :request do
  describe "POST /products/:product_id/product_view" do
    it "requires sign in" do
      product = create(:product)
      post product_product_view_path(product), as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "records a first view for the current user" do
      user = create(:user)
      product = create(:product)
      sign_in user

      expect {
        post product_product_view_path(product), as: :json
      }.to change { ProductView.count }.by(1)

      expect(response).to have_http_status(:no_content)
      view = ProductView.find_by(user: user, product: product)
      expect(view.last_viewed_at).to be_present
    end

    it "updates the timestamp without creating a duplicate row on a revisit" do
      user = create(:user)
      product = create(:product)
      sign_in user
      post product_product_view_path(product), as: :json
      view = ProductView.find_by(user: user, product: product)

      travel 1.hour do
        expect {
          post product_product_view_path(product), as: :json
        }.not_to change { ProductView.count }

        expect(response).to have_http_status(:no_content)
        expect(view.reload.last_viewed_at).to be_within(1.second).of(Time.current)
      end
    end

    it "does not record a view for a product that does not exist" do
      user = create(:user)
      sign_in user

      expect {
        post product_product_view_path(999_999), as: :json
      }.not_to change { ProductView.count }

      expect(response).to have_http_status(:not_found)
    end

    it "scopes the recorded view to the authenticated user, not any client-supplied id" do
      user = create(:user)
      other = create(:user)
      product = create(:product)
      sign_in user

      post product_product_view_path(product), params: { user_id: other.id }, as: :json

      expect(ProductView.exists?(user: user, product: product)).to be true
      expect(ProductView.exists?(user: other, product: product)).to be false
    end
  end

  describe "GET /product_views" do
    it "requires sign in" do
      get product_views_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "lists only the current user's recently viewed products, newest first" do
      user = create(:user)
      other = create(:user)
      older = create(:product, name: "Older Widget")
      newer = create(:product, name: "Newer Widget")
      not_mine = create(:product, name: "Someone Elses Widget")

      create(:product_view, user: user, product: older, last_viewed_at: 2.days.ago)
      create(:product_view, user: user, product: newer, last_viewed_at: 1.day.ago)
      create(:product_view, user: other, product: not_mine, last_viewed_at: 1.day.ago)
      sign_in user

      get product_views_path

      expect(response.body).to include("Newer Widget")
      expect(response.body).to include("Older Widget")
      expect(response.body).not_to include("Someone Elses Widget")
      expect(response.body.index("Newer Widget")).to be < response.body.index("Older Widget")
    end

    it "excludes views older than 7 days" do
      user = create(:user)
      in_window = create(:product, name: "Still Fresh Widget")
      expired = create(:product, name: "Too Old Widget")
      create(:product_view, user: user, product: in_window, last_viewed_at: 6.days.ago)
      create(:product_view, user: user, product: expired, last_viewed_at: 8.days.ago)
      sign_in user

      get product_views_path

      expect(response.body).to include("Still Fresh Widget")
      expect(response.body).not_to include("Too Old Widget")
    end

    it "excludes products that have been deleted" do
      user = create(:user)
      product = create(:product, name: "Deleted Widget")
      create(:product_view, user: user, product: product)
      product.destroy!
      sign_in user

      get product_views_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Deleted Widget")
      expect(ProductView.where(product_id: product.id)).to be_empty
    end

    it "shows an empty state when the user has no recent views" do
      user = create(:user)
      sign_in user

      get product_views_path

      expect(response.body).to include("You haven't viewed any products in the last 7 days.")
    end

    it "keeps out-of-stock products visible" do
      user = create(:user)
      product = create(:product, name: "Sold Out Widget", stock_quantity: 0)
      create(:product_view, user: user, product: product)
      sign_in user

      get product_views_path

      expect(response.body).to include("Sold Out Widget")
      expect(response.body).to include("Out of stock")
    end

    it "renders a retry-able error state when loading fails" do
      user = create(:user)
      sign_in user
      allow_any_instance_of(User)
        .to receive(:product_views).and_raise(ActiveRecord::StatementInvalid, "boom")

      get product_views_path

      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("Couldn't load your recently viewed products right now.")
      expect(response.body).to include("Retry")
    end
  end

  describe "logout / account switching" do
    it "does not leak one user's history into another user's session" do
      user_a = create(:user)
      user_b = create(:user)
      product_a = create(:product, name: "User A Widget")
      product_b = create(:product, name: "User B Widget")
      create(:product_view, user: user_a, product: product_a)
      create(:product_view, user: user_b, product: product_b)

      sign_in user_a
      get product_views_path
      expect(response.body).to include("User A Widget")
      expect(response.body).not_to include("User B Widget")

      sign_out user_a
      sign_in user_b
      get product_views_path
      expect(response.body).to include("User B Widget")
      expect(response.body).not_to include("User A Widget")
    end
  end
end
