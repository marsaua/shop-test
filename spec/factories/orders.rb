FactoryBot.define do
  factory :order do
    user
    status { :pending }
    total_cents { 0 }
  end
end
