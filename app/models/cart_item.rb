class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :product

  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :product_id, uniqueness: { scope: :cart_id }

  # Stock availability is intentionally NOT checked here. CheckoutService
  # is the single source of truth for stock availability — see the
  # "Stock is checked at checkout, not at add-to-cart" section of
  # docs/superpowers/specs/2026-09-08-online-store-design.md. A cart may
  # legitimately hold more of a product than is currently in stock; that
  # surfaces as an out-of-stock failure at checkout, not here. Do not
  # "fix" this by adding a stock check to this model or its controller.
end
