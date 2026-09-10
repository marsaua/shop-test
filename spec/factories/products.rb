FactoryBot.define do
  factory :product do
    sequence(:name) { |n| "Product #{n}" }
    sequence(:sku) { |n| "SKU-#{n}" }
    description { "A great product." }
    price_cents { 1000 }
    stock_quantity { 10 }
    brand { "Acme" }
    category { :accessories }
  end
end
