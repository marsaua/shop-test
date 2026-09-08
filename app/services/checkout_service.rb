# Runs a checkout against our own simulated PaymentCard wallet — never a
# real bank or payment processor. See the "Checkout flow & payment
# simulation" section of docs/superpowers/specs/2026-09-08-online-store-design.md.
class CheckoutService
  Result = Struct.new(:success?, :order, :error, keyword_init: true)

  def initialize(user:, card_number:)
    @user = user
    @card_number = card_number
  end

  def call
    abort_reason = nil

    result = ActiveRecord::Base.transaction do
      cart = @user.cart
      cart.lock!

      cart_items = cart.cart_items.includes(:product).to_a
      if cart_items.empty?
        abort_reason = "empty_cart"
        raise ActiveRecord::Rollback
      end

      products = Product.lock.where(id: cart_items.map(&:product_id)).order(:id).index_by(&:id)

      out_of_stock = cart_items.find { |item| products.fetch(item.product_id).stock_quantity < item.quantity }
      if out_of_stock
        abort_reason = "out_of_stock"
        raise ActiveRecord::Rollback
      end

      order = @user.orders.create!(status: :pending, total_cents: 0)
      total_cents = cart_items.sum { |item| products.fetch(item.product_id).price_cents * item.quantity }

      cart_items.each do |item|
        product = products.fetch(item.product_id)
        order.order_items.create!(
          product: product,
          product_name: product.name,
          unit_price_cents: product.price_cents,
          quantity: item.quantity
        )
      end
      order.update!(total_cents: total_cents)

      sanitized_card_number = @card_number.to_s.gsub(/[\s-]/, "")

      if sanitized_card_number.blank? || !sanitized_card_number.match?(/\A\d+\z/)
        order.update!(status: :failed, failure_reason: "invalid_card")
        next Result.new(success?: false, order: order, error: "invalid_card")
      end

      card = PaymentCard.lock.find_by(card_number: sanitized_card_number)

      if card.nil?
        order.update!(status: :failed, failure_reason: "invalid_card")
        next Result.new(success?: false, order: order, error: "invalid_card")
      end

      if card.balance_cents < total_cents
        order.update!(status: :failed, failure_reason: "insufficient_funds")
        next Result.new(success?: false, order: order, error: "insufficient_funds")
      end

      card.update!(balance_cents: card.balance_cents - total_cents)
      cart_items.each do |item|
        product = products.fetch(item.product_id)
        product.update!(stock_quantity: product.stock_quantity - item.quantity)
      end
      order.update!(status: :paid, card_last4: sanitized_card_number.last(4))
      cart.cart_items.destroy_all

      Result.new(success?: true, order: order, error: nil)
    end

    result || Result.new(success?: false, order: nil, error: abort_reason)
  end
end
