require "rails_helper"

RSpec.describe "Cart items", type: :request do
  describe "POST /cart_items" do
    it "requires sign in" do
      product = create(:product)
      post cart_items_path, params: { product_id: product.id }
      expect(response).to redirect_to(new_user_session_path)
    end

    it "adds a product to the current user's cart" do
      user = create(:user)
      product = create(:product)
      sign_in user

      expect {
        post cart_items_path, params: { product_id: product.id, quantity: 2 }
      }.to change { user.cart.cart_items.count }.by(1)

      expect(user.cart.cart_items.first.quantity).to eq(2)
    end

    it "allows adding more of a product than is currently in stock" do
      user = create(:user)
      product = create(:product, stock_quantity: 1)
      sign_in user

      post cart_items_path, params: { product_id: product.id, quantity: 99 }

      expect(user.cart.cart_items.first.quantity).to eq(99)
    end

    it "increments quantity when the same product is added again" do
      user = create(:user)
      product = create(:product)
      sign_in user
      user.cart.cart_items.create!(product: product, quantity: 1)

      post cart_items_path, params: { product_id: product.id, quantity: 2 }

      expect(user.cart.cart_items.sole.quantity).to eq(3)
    end
  end

  describe "PATCH /cart_items/:id" do
    it "is forbidden when updating another user's cart item" do
      owner = create(:user)
      item = owner.cart.cart_items.create!(product: create(:product), quantity: 1)
      sign_in create(:user)

      patch cart_item_path(item), params: { quantity: 5 }

      expect(response).to have_http_status(:forbidden)
    end

    it "lets the owner update the quantity" do
      user = create(:user)
      item = user.cart.cart_items.create!(product: create(:product), quantity: 1)
      sign_in user

      patch cart_item_path(item), params: { quantity: 5 }

      expect(item.reload.quantity).to eq(5)
    end
  end

  describe "DELETE /cart_items/:id" do
    it "removes the item from the owner's cart" do
      user = create(:user)
      item = user.cart.cart_items.create!(product: create(:product), quantity: 1)
      sign_in user

      expect { delete cart_item_path(item) }.to change { user.cart.cart_items.count }.by(-1)
    end

    it "is forbidden for another user" do
      owner = create(:user)
      item = owner.cart.cart_items.create!(product: create(:product), quantity: 1)
      sign_in create(:user)

      delete cart_item_path(item)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
