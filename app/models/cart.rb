class Cart < ApplicationRecord
  belongs_to :user
  has_many :cart_items, dependent: :destroy
  has_many :products, through: :cart_items

  def total_cents
    cart_items.joins(:product).sum("products.price_cents * cart_items.quantity")
  end
end
