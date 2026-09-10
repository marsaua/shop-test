require "rails_helper"

RSpec.describe FavoritePolicy do
  describe "#create?, #destroy?" do
    it "is true only for the favorite's own owner" do
      owner = create(:user)
      other = create(:user)
      favorite = create(:favorite, user: owner)

      expect(described_class.new(owner, favorite).create?).to be true
      expect(described_class.new(owner, favorite).destroy?).to be true

      expect(described_class.new(other, favorite).destroy?).to be false
      expect(described_class.new(nil, favorite).destroy?).to be false
    end
  end
end
