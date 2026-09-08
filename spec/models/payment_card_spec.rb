require "rails_helper"

RSpec.describe PaymentCard, type: :model do
  subject { build(:payment_card) }

  it { is_expected.to validate_presence_of(:card_number) }
  it { is_expected.to validate_uniqueness_of(:card_number) }
  it { is_expected.to validate_numericality_of(:balance_cents).is_greater_than_or_equal_to(0) }
end
