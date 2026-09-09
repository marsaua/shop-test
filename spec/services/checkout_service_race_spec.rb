require "rails_helper"
require "database_cleaner/active_record"
require_relative "../support/lock_contention"

RSpec.describe CheckoutService, "concurrency", :race_condition, type: :model do
  include LockContention

  self.use_transactional_tests = false

  before { DatabaseCleaner.strategy = :truncation }
  after { DatabaseCleaner.clean }

  it "allows only one of two concurrent checkouts against the same cart to succeed" do
    user = create(:user)
    product = create(:product, price_cents: 1000, stock_quantity: 5)
    user.cart.cart_items.create!(product: product, quantity: 1)
    card = create(:payment_card, balance_cents: 100_000)

    jobs = Array.new(2) { -> { CheckoutService.new(user: user, card_number: card.card_number).call } }
    outcomes = run_under_forced_contention(user.cart, jobs)

    expect(outcomes.count(&:success?)).to eq(1)
    losing_result = outcomes.reject(&:success?).first
    expect(losing_result.error).to eq("empty_cart")
    expect(Order.where(user: user, status: :paid).count).to eq(1)
    expect(product.reload.stock_quantity).to eq(4)
    expect(card.reload.balance_cents).to eq(99_000)
  end

  it "does not double-spend a shared card across two different users checking out concurrently" do
    card = create(:payment_card, balance_cents: 15_000)
    user_a = create(:user)
    user_b = create(:user)
    product_a = create(:product, price_cents: 10_000, stock_quantity: 5)
    product_b = create(:product, price_cents: 10_000, stock_quantity: 5)
    user_a.cart.cart_items.create!(product: product_a, quantity: 1)
    user_b.cart.cart_items.create!(product: product_b, quantity: 1)

    jobs = [ user_a, user_b ].map { |user| -> { CheckoutService.new(user: user, card_number: card.card_number).call } }
    outcomes = run_under_forced_contention(card, jobs)

    expect(outcomes.count(&:success?)).to eq(1)
    losing_result = outcomes.reject(&:success?).first
    expect(losing_result.error).to eq("insufficient_funds")
    expect(card.reload.balance_cents).to eq(5_000)
  end
end
