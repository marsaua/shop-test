require "rails_helper"

RSpec.describe Product, type: :model do
  it { is_expected.to have_many(:cart_items).dependent(:destroy) }
  it { is_expected.to have_many(:order_items).dependent(:restrict_with_error) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_numericality_of(:price_cents).is_greater_than(0) }
  it { is_expected.to validate_numericality_of(:stock_quantity).is_greater_than_or_equal_to(0) }

  describe ".in_stock" do
    it "excludes products with zero stock" do
      in_stock = create(:product, stock_quantity: 1)
      out_of_stock = create(:product, stock_quantity: 0)

      expect(Product.in_stock).to include(in_stock)
      expect(Product.in_stock).not_to include(out_of_stock)
    end
  end

  describe ".price_gteq / .price_lteq" do
    it "filters by a price range" do
      cheap = create(:product, price_cents: 500)
      pricey = create(:product, price_cents: 5000)

      result = Product.price_gteq(1000).price_lteq(6000)
      expect(result).to include(pricey)
      expect(result).not_to include(cheap)
    end
  end

  describe ".sorted" do
    it "sorts by price descending" do
      cheap = create(:product, price_cents: 500)
      pricey = create(:product, price_cents: 5000)

      expect(Product.sorted("price_desc").to_a).to eq([pricey, cheap])
    end

    it "falls back to name ascending for an unknown key" do
      b = create(:product, name: "B Product")
      a = create(:product, name: "A Product")

      expect(Product.sorted("nonsense").to_a).to eq([a, b])
    end
  end

  describe "image attachment" do
    it "can have an image attached, and works fine without one" do
      product = create(:product)
      expect(product.image).not_to be_attached

      product.image.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/test_image.png")),
        filename: "test_image.png",
        content_type: "image/png"
      )
      expect(product.image).to be_attached
    end
  end
end
