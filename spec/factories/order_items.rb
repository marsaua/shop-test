FactoryBot.define do
  factory :order_item do
    order
    product
    product_name { product.name }
    unit_price_cents { product.price_cents }
    quantity { 1 }
  end
end
