require "rails_helper"

RSpec.describe Favorite, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:product) }

  it "does not allow the same product to be favorited twice by the same user" do
    user = create(:user)
    product = create(:product)
    create(:favorite, user: user, product: product)

    duplicate = build(:favorite, user: user, product: product)

    expect(duplicate).not_to be_valid
  end

  it "allows different users to favorite the same product" do
    product = create(:product)
    create(:favorite, user: create(:user), product: product)

    other = build(:favorite, user: create(:user), product: product)

    expect(other).to be_valid
  end
end
