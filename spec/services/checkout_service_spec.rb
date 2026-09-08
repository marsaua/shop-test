require "rails_helper"

RSpec.describe CheckoutService do
  describe "a successful checkout" do
    it "pays the order, deducts the card, decrements stock, and clears the cart" do
      user = create(:user)
      product = create(:product, price_cents: 1000, stock_quantity: 5)
      user.cart.cart_items.create!(product: product, quantity: 2)
      card = create(:payment_card, balance_cents: 5000)

      result = described_class.new(user: user, card_number: card.card_number).call

      expect(result).to be_success
      expect(result.order).to be_paid
      expect(result.order.total_cents).to eq(2000)
      expect(result.order.card_last4).to eq(card.card_number.last(4))
      expect(result.order.order_items.sole).to have_attributes(
        product_name: product.name, unit_price_cents: 1000, quantity: 2
      )

      expect(card.reload.balance_cents).to eq(3000)
      expect(product.reload.stock_quantity).to eq(3)
      expect(user.cart.cart_items.count).to eq(0)
    end

    it "sanitizes whitespace and dashes in the card number before matching" do
      user = create(:user)
      product = create(:product, price_cents: 1000, stock_quantity: 5)
      user.cart.cart_items.create!(product: product, quantity: 1)
      card = create(:payment_card, card_number: "4242424242424242", balance_cents: 5000)

      result = described_class.new(user: user, card_number: " 4242-4242-4242-4242 ").call

      expect(result).to be_success
      expect(result.order.card_last4).to eq("4242")
    end
  end
end
