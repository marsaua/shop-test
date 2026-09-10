FactoryBot.define do
  factory :product_popularity_stat do
    product
    viewers_count { 1 }
    calculated_at { Time.current }
  end
end
