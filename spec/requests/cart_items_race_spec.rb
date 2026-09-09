require "rails_helper"
require "database_cleaner/active_record"
require_relative "../support/lock_contention"

RSpec.describe "Cart item concurrency", :race_condition, type: :request do
  include LockContention

  self.use_transactional_tests = false

  before { DatabaseCleaner.strategy = :truncation }
  after { DatabaseCleaner.clean }

  it "does not silently lose a cart item added while a checkout is running against the same cart" do
    user = create(:user)
    existing_product = create(:product, price_cents: 1000, stock_quantity: 5)
    new_product = create(:product, price_cents: 500, stock_quantity: 5)
    user.cart.cart_items.create!(product: existing_product, quantity: 1)
    card = create(:payment_card, balance_cents: 100_000)

    # Sessions are authenticated up front, sequentially, before the race
    # starts: Warden's sign-in test helper queues the next login onto a
    # single process-wide queue, so signing in from two threads racing
    # each other would risk one session consuming the other's login.
    add_item_session = login_session(user)

    checkout_job = -> { CheckoutService.new(user: user, card_number: card.card_number).call }
    add_item_job = lambda do
      add_item_session.post "/cart_items", params: { product_id: new_product.id, quantity: 1 }
      add_item_session.response.status
    end

    checkout_result, = run_under_forced_contention(user.cart, [ checkout_job, add_item_job ])

    expect(checkout_result).to be_success

    order = checkout_result.order
    expect(order.order_items.pluck(:product_id)).to include(existing_product.id)

    included_in_order = order.order_items.exists?(product_id: new_product.id)
    remains_in_cart = CartItem.exists?(cart_id: user.cart.id, product_id: new_product.id)
    expect(included_in_order || remains_in_cart).to be(true)
  end

  it "produces the correct final quantity when the same product is added twice concurrently" do
    user = create(:user)
    product = create(:product, stock_quantity: 100)

    # Two independent, already-authenticated sessions for the same user —
    # authenticated up front, sequentially, for the same reason as above.
    session_1 = login_session(user)
    session_2 = login_session(user)

    add_job = lambda do |session|
      session.post "/cart_items", params: { product_id: product.id, quantity: 1 }
      session.response.status
    end

    statuses = run_under_forced_contention(user.cart, [ -> { add_job.call(session_1) }, -> { add_job.call(session_2) } ])

    expect(statuses).to all(eq(302))
    items = CartItem.where(cart_id: user.cart.id, product_id: product.id)
    expect(items.count).to eq(1)
    expect(items.sole.quantity).to eq(2)
  end
end
