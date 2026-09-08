require "rails_helper"

RSpec.describe CartItemPolicy do
  describe "#create?, #update?, #destroy?" do
    it "is true only for the cart's own owner" do
      owner = create(:user)
      other = create(:user)
      item = create(:cart_item, cart: owner.cart)

      expect(described_class.new(owner, item).create?).to be true
      expect(described_class.new(owner, item).update?).to be true
      expect(described_class.new(owner, item).destroy?).to be true

      expect(described_class.new(other, item).update?).to be false
      expect(described_class.new(nil, item).update?).to be false
    end
  end
end
