require "rails_helper"

RSpec.describe "Checkout", type: :request do
  def sign_in_with_cart(quantity: 1, product_stock: 10, product_price_cents: 1000)
    user = create(:user)
    product = create(:product, stock_quantity: product_stock, price_cents: product_price_cents)
    user.cart.cart_items.create!(product: product, quantity: quantity)
    sign_in user
    [user, product]
  end

  it "requires sign in" do
    post checkout_path, params: { card_number: "4242424242424242" }
    expect(response).to redirect_to(new_user_session_path)
  end

  it "succeeds with a valid, sufficiently funded card" do
    card = create(:payment_card, balance_cents: 100_000)
    user, = sign_in_with_cart

    post checkout_path, params: { card_number: card.card_number }

    order = user.orders.last
    expect(order).to be_paid
    expect(response).to redirect_to(order_path(order))
  end

  it "fails with insufficient funds and leaves the cart intact" do
    card = create(:payment_card, balance_cents: 1)
    user, = sign_in_with_cart

    post checkout_path, params: { card_number: card.card_number }

    order = user.orders.last
    expect(order).to be_failed
    expect(order.failure_reason).to eq("insufficient_funds")
    expect(user.cart.cart_items.count).to eq(1)
  end

  it "fails with a card number that doesn't exist" do
    user, = sign_in_with_cart

    post checkout_path, params: { card_number: "0000000000000000" }

    expect(user.orders.last.failure_reason).to eq("invalid_card")
  end

  it "fails gracefully instead of erroring on a malformed card number" do
    user, = sign_in_with_cart

    post checkout_path, params: { card_number: "abcd-not-a-card" }

    expect(response).to have_http_status(:redirect)
    expect(user.orders.last.failure_reason).to eq("invalid_card")
  end

  it "rejects checkout with an empty cart" do
    user = create(:user)
    card = create(:payment_card, balance_cents: 100_000)
    sign_in user

    expect { post checkout_path, params: { card_number: card.card_number } }.not_to change(Order, :count)
  end

  it "fails when the cart quantity exceeds available stock" do
    card = create(:payment_card, balance_cents: 100_000)
    user, product = sign_in_with_cart(quantity: 5, product_stock: 2)

    expect { post checkout_path, params: { card_number: card.card_number } }.not_to change(Order, :count)
    expect(product.reload.stock_quantity).to eq(2)
  end
end
