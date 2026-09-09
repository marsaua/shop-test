FactoryBot.define do
  factory :cart_item do
    cart { association(:user, strategy: :create).cart }
    product
    quantity { 1 }
  end
end
