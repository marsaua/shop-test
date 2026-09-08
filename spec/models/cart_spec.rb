require "rails_helper"

RSpec.describe Cart, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:cart_items).dependent(:destroy) }

  describe "#total_cents" do
    it "sums price times quantity across all items" do
      cart = create(:user).cart
      product_a = create(:product, price_cents: 1000)
      product_b = create(:product, price_cents: 500)
      cart.cart_items.create!(product: product_a, quantity: 2)
      cart.cart_items.create!(product: product_b, quantity: 3)

      expect(cart.total_cents).to eq((1000 * 2) + (500 * 3))
    end

    it "is zero for an empty cart" do
      cart = create(:user).cart
      expect(cart.total_cents).to eq(0)
    end
  end
end
