require "rails_helper"

RSpec.describe "Favorites", type: :request do
  describe "POST /products/:product_id/favorite" do
    it "requires sign in" do
      product = create(:product)
      post product_favorite_path(product), as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a favorite for the current user and returns the new count" do
      user = create(:user)
      product = create(:product)
      sign_in user

      expect {
        post product_favorite_path(product), as: :json
      }.to change { user.favorites.count }.by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["favorited"]).to be true
      expect(body["count"]).to eq(1)
    end

    it "is idempotent when the product is already favorited" do
      user = create(:user)
      product = create(:product)
      create(:favorite, user: user, product: product)
      sign_in user

      expect {
        post product_favorite_path(product), as: :json
      }.not_to change { user.favorites.count }

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["count"]).to eq(1)
    end
  end

  describe "DELETE /products/:product_id/favorite" do
    it "requires sign in" do
      product = create(:product)
      delete product_favorite_path(product), as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "removes the current user's favorite" do
      user = create(:user)
      product = create(:product)
      create(:favorite, user: user, product: product)
      sign_in user

      expect {
        delete product_favorite_path(product), as: :json
      }.to change { user.favorites.count }.by(-1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["favorited"]).to be false
      expect(body["count"]).to eq(0)
    end

    it "does not touch another user's favorite of the same product" do
      owner = create(:user)
      product = create(:product)
      create(:favorite, user: owner, product: product)
      sign_in create(:user)

      delete product_favorite_path(product), as: :json

      expect(owner.favorites.count).to eq(1)
    end

    it "is idempotent when the product is not favorited" do
      user = create(:user)
      product = create(:product)
      sign_in user

      delete product_favorite_path(product), as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["favorited"]).to be false
    end
  end

  describe "GET /favorites" do
    it "is accessible to guests" do
      get favorites_path
      expect(response).to have_http_status(:ok)
    end

    it "lists only the current user's favorited products" do
      user = create(:user)
      other = create(:user)
      mine = create(:product, name: "My Favorite Widget")
      not_mine = create(:product, name: "Someone Elses Widget")
      create(:favorite, user: user, product: mine)
      create(:favorite, user: other, product: not_mine)
      sign_in user

      get favorites_path

      expect(response.body).to include("My Favorite Widget")
      expect(response.body).not_to include("Someone Elses Widget")
    end
  end

  describe "POST /favorites/merge" do
    it "requires sign in" do
      post merge_favorites_path, params: { product_ids: [ 1 ] }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates favorites for the given product ids, skipping invalid and missing ones" do
      user = create(:user)
      keep_a = create(:product)
      keep_b = create(:product)
      sign_in user

      post merge_favorites_path,
        params: { product_ids: [ keep_a.id, keep_b.id, 0, "not-a-number" ] },
        as: :json

      expect(response).to have_http_status(:ok)
      expect(user.favorites.pluck(:product_id)).to contain_exactly(keep_a.id, keep_b.id)
      body = JSON.parse(response.body)
      expect(body["count"]).to eq(2)
      expect(body["favorited_product_ids"]).to contain_exactly(keep_a.id, keep_b.id)
    end

    it "does not duplicate favorites the user already has" do
      user = create(:user)
      product = create(:product)
      create(:favorite, user: user, product: product)
      sign_in user

      expect {
        post merge_favorites_path, params: { product_ids: [ product.id ] }, as: :json
      }.not_to change { user.favorites.count }
    end
  end
end
