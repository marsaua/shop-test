require "rails_helper"

RSpec.describe ProductViewPolicy do
  describe "#create?" do
    it "is true only for the view's own owner" do
      owner = create(:user)
      other = create(:user)
      product_view = create(:product_view, user: owner)

      expect(described_class.new(owner, product_view).create?).to be true
      expect(described_class.new(other, product_view).create?).to be false
      expect(described_class.new(nil, product_view).create?).to be false
    end
  end

  describe "#index?" do
    it "is true only for signed-in users" do
      expect(described_class.new(create(:user), ProductView).index?).to be true
      expect(described_class.new(nil, ProductView).index?).to be false
    end
  end
end
