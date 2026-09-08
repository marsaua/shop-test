FactoryBot.define do
  factory :payment_card do
    sequence(:card_number) { |n| format("42424242%08d", n) }
    holder_name { "Test Cardholder" }
    balance_cents { 10_000 }
  end
end
