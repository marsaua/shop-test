require "rails_helper"

RSpec.describe ProductPolicy do
  let(:guest) { nil }
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:product) { Product.new }

  describe "#index? and #show?" do
    it "is true for everyone, including guests" do
      expect(described_class.new(guest, product).index?).to be true
      expect(described_class.new(user, product).index?).to be true
      expect(described_class.new(admin, product).index?).to be true

      expect(described_class.new(guest, product).show?).to be true
      expect(described_class.new(user, product).show?).to be true
    end
  end

  describe "#create?, #update?, #destroy?" do
    it "denies guests and regular users" do
      expect(described_class.new(guest, product).create?).to be false
      expect(described_class.new(user, product).create?).to be false
      expect(described_class.new(user, product).update?).to be false
      expect(described_class.new(user, product).destroy?).to be false
    end

    it "grants admins" do
      expect(described_class.new(admin, product).create?).to be true
      expect(described_class.new(admin, product).update?).to be true
      expect(described_class.new(admin, product).destroy?).to be true
    end
  end
end
