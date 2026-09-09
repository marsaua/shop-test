require "rails_helper"

RSpec.describe CartItem, type: :model do
  it { is_expected.to belong_to(:cart) }
  it { is_expected.to belong_to(:product) }
  it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(1).only_integer }

  it "does not allow the same product twice in one cart" do
    cart = create(:user).cart
    product = create(:product)
    create(:cart_item, cart: cart, product: product)

    duplicate = build(:cart_item, cart: cart, product: product)

    expect(duplicate).not_to be_valid
  end

  it "does not validate against product stock" do
    product = create(:product, stock_quantity: 0)
    cart_item = build(:cart_item, product: product, quantity: 99)

    expect(cart_item).to be_valid
  end
end
