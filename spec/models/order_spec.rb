require "rails_helper"

RSpec.describe Order, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:order_items).dependent(:destroy) }
  it { is_expected.to define_enum_for(:status).with_values(pending: 0, paid: 1, failed: 2) }
  it { is_expected.to validate_numericality_of(:total_cents).is_greater_than_or_equal_to(0) }
end
