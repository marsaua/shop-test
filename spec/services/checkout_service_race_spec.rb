require "rails_helper"
require "database_cleaner/active_record"

RSpec.describe CheckoutService, "double-checkout race", :race_condition, type: :model do
  self.use_transactional_tests = false

  before { DatabaseCleaner.strategy = :truncation }
  after { DatabaseCleaner.clean }

  it "allows only one of two concurrent checkouts against the same cart to succeed" do
    user = create(:user)
    product = create(:product, price_cents: 1000, stock_quantity: 5)
    user.cart.cart_items.create!(product: product, quantity: 1)
    card = create(:payment_card, balance_cents: 100_000)

    results = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          results << CheckoutService.new(user: user, card_number: card.card_number).call
        end
      end
    end
    threads.each(&:join)

    outcomes = Array.new(2) { results.pop }

    expect(outcomes.count(&:success?)).to eq(1)
    expect(Order.where(user: user, status: :paid).count).to eq(1)
    expect(product.reload.stock_quantity).to eq(4)
    expect(card.reload.balance_cents).to eq(99_000)
  end
end
