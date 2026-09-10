FactoryBot.define do
  factory :product_view do
    user
    product
    last_viewed_at { Time.current }
  end
end
