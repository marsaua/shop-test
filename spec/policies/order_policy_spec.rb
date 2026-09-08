require "rails_helper"

RSpec.describe OrderPolicy do
  describe "#show?" do
    it "allows the order's owner and any admin, denies everyone else" do
      owner = create(:user)
      admin = create(:user, :admin)
      other = create(:user)
      order = create(:order, user: owner)

      expect(described_class.new(owner, order).show?).to be true
      expect(described_class.new(admin, order).show?).to be true
      expect(described_class.new(other, order).show?).to be false
      expect(described_class.new(nil, order).show?).to be false
    end
  end

  describe "Scope" do
    it "restricts regular users to their own orders and lets admins see all" do
      owner = create(:user)
      admin = create(:user, :admin)
      order = create(:order, user: owner)
      other_order = create(:order)

      expect(described_class::Scope.new(owner, Order).resolve).to contain_exactly(order)
      expect(described_class::Scope.new(admin, Order).resolve).to include(order, other_order)
    end
  end
end
