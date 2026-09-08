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

  describe "insufficient funds" do
    it "fails the order, leaves the cart intact, and does not touch stock or balance" do
      user = create(:user)
      product = create(:product, price_cents: 1000, stock_quantity: 5)
      user.cart.cart_items.create!(product: product, quantity: 2)
      card = create(:payment_card, balance_cents: 100)

      result = described_class.new(user: user, card_number: card.card_number).call

      expect(result).not_to be_success
      expect(result.error).to eq("insufficient_funds")
      expect(result.order).to be_failed
      expect(result.order.failure_reason).to eq("insufficient_funds")
      expect(card.reload.balance_cents).to eq(100)
      expect(product.reload.stock_quantity).to eq(5)
      expect(user.cart.cart_items.count).to eq(1)
    end
  end

  describe "invalid card" do
    it "fails the order when no card matches the number" do
      user = create(:user)
      user.cart.cart_items.create!(product: create(:product), quantity: 1)

      result = described_class.new(user: user, card_number: "0000000000000000").call

      expect(result).not_to be_success
      expect(result.error).to eq("invalid_card")
      expect(result.order).to be_failed
      expect(result.order.failure_reason).to eq("invalid_card")
      expect(user.cart.cart_items.count).to eq(1)
    end
  end

  describe "malformed card numbers" do
    ["", "    ", "abcd1234abcd1234"].each do |bad_number|
      it "fails gracefully as invalid_card for #{bad_number.inspect} instead of raising" do
        user = create(:user)
        user.cart.cart_items.create!(product: create(:product), quantity: 1)

        result = nil
        expect { result = described_class.new(user: user, card_number: bad_number).call }.not_to raise_error

        expect(result).not_to be_success
        expect(result.error).to eq("invalid_card")
        expect(result.order.failure_reason).to eq("invalid_card")
      end
    end
  end

  describe "empty cart" do
    it "fails without creating an order" do
      user = create(:user)
      card = create(:payment_card, balance_cents: 100_000)

      result = described_class.new(user: user, card_number: card.card_number).call

      expect(result).not_to be_success
      expect(result.error).to eq("empty_cart")
      expect(result.order).to be_nil
      expect(Order.count).to eq(0)
    end
  end

  describe "out of stock" do
    it "fails without creating an order and without touching stock" do
      user = create(:user)
      product = create(:product, stock_quantity: 1)
      user.cart.cart_items.create!(product: product, quantity: 5)
      card = create(:payment_card, balance_cents: 100_000)

      result = described_class.new(user: user, card_number: card.card_number).call

      expect(result).not_to be_success
      expect(result.error).to eq("out_of_stock")
      expect(result.order).to be_nil
      expect(Order.count).to eq(0)
      expect(product.reload.stock_quantity).to eq(1)
    end
  end
end
