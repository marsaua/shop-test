require "rails_helper"

RSpec.describe OrderItem, type: :model do
  it { is_expected.to belong_to(:order) }
  it { is_expected.to belong_to(:product) }
  it { is_expected.to validate_presence_of(:product_name) }
  it { is_expected.to validate_numericality_of(:unit_price_cents).is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0).only_integer }

  it "keeps its snapshot even after the product's price changes" do
    product = create(:product, price_cents: 1000)
    item = create(:order_item, product: product, unit_price_cents: 1000)

    product.update!(price_cents: 5000)

    expect(item.reload.unit_price_cents).to eq(1000)
  end
end
