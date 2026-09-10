require "rails_helper"

RSpec.describe ProductPopularityStat, type: :model do
  it { is_expected.to belong_to(:product) }

  describe ".top" do
    it "only returns stats with a positive viewer count" do
      popular = create(:product)
      never_viewed = create(:product)
      create(:product_popularity_stat, product: popular, viewers_count: 3)
      create(:product_popularity_stat, product: never_viewed, viewers_count: 0)

      expect(ProductPopularityStat.top(user: nil).map(&:product)).to contain_exactly(popular)
    end

    it "orders by viewer count descending, breaking ties by product id for a stable order" do
      low = create(:product)
      high = create(:product)
      tie_a = create(:product)
      tie_b = create(:product)
      create(:product_popularity_stat, product: low, viewers_count: 1)
      create(:product_popularity_stat, product: high, viewers_count: 10)
      create(:product_popularity_stat, product: tie_a, viewers_count: 5)
      create(:product_popularity_stat, product: tie_b, viewers_count: 5)
      expected_tie_order = [ tie_a, tie_b ].sort_by(&:id)

      result = ProductPopularityStat.top(user: nil).map(&:product)

      expect(result).to eq([ high, *expected_tie_order, low ])
    end

    it "limits to the requested number of results" do
      create_list(:product, 15).each { |product| create(:product_popularity_stat, product: product, viewers_count: 1) }

      expect(ProductPopularityStat.top(user: nil, limit: 12).count).to eq(12)
    end

    it "is removed automatically when its product is destroyed" do
      product = create(:product)
      create(:product_popularity_stat, product: product, viewers_count: 5)

      product.destroy!

      expect(ProductPopularityStat.exists?(product_id: product.id)).to be false
    end
  end
end
