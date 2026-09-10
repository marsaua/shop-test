require "rails_helper"

RSpec.describe Product, type: :model do
  subject { build(:product) }

  it { is_expected.to have_many(:cart_items).dependent(:destroy) }
  it { is_expected.to have_many(:order_items).dependent(:restrict_with_error) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_numericality_of(:price_cents).is_greater_than(0) }
  it { is_expected.to validate_numericality_of(:stock_quantity).is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_presence_of(:sku) }
  it { is_expected.to validate_uniqueness_of(:sku) }
  it { is_expected.to validate_presence_of(:brand) }
  it { is_expected.to validate_presence_of(:category) }
  it { is_expected.to validate_numericality_of(:warranty_months).is_greater_than_or_equal_to(0).allow_nil }
  it { is_expected.to validate_numericality_of(:weight_grams).is_greater_than(0).allow_nil }
  it { is_expected.to define_enum_for(:category).with_values(
    smartphones: 0, laptops: 1, tvs_and_monitors: 2, headphones: 3, accessories: 4, other: 5
  ) }

  describe "previous_price_cents" do
    it "is valid when greater than price_cents" do
      product = build(:product, price_cents: 1000, previous_price_cents: 1500)
      expect(product).to be_valid
    end

    it "is invalid when less than or equal to price_cents" do
      product = build(:product, price_cents: 1000, previous_price_cents: 1000)
      expect(product).not_to be_valid
      expect(product.errors[:previous_price_cents]).to be_present
    end

    it "is optional" do
      product = build(:product, previous_price_cents: nil)
      expect(product).to be_valid
    end
  end

  describe "specifications" do
    it "parses a JSON string into a hash" do
      product = build(:product, specifications: '{"ram_gb": 8}')
      expect(product.specifications).to eq("ram_gb" => 8)
    end

    it "is invalid when given a non-JSON string" do
      product = build(:product, specifications: "not json")
      expect(product).not_to be_valid
      expect(product.errors[:specifications]).to be_present
    end

    it "defaults to an empty hash" do
      product = build(:product)
      expect(product.specifications).to eq({})
    end
  end

  describe "#discounted?" do
    it "is true when previous_price_cents exceeds price_cents" do
      product = build(:product, price_cents: 1000, previous_price_cents: 1500)
      expect(product).to be_discounted
    end

    it "is false when there is no previous price" do
      product = build(:product, previous_price_cents: nil)
      expect(product).not_to be_discounted
    end
  end

  describe "#low_stock? / #out_of_stock?" do
    it "treats zero stock as out of stock, not low stock" do
      product = build(:product, stock_quantity: 0)
      expect(product).to be_out_of_stock
      expect(product).not_to be_low_stock
    end

    it "treats a small positive stock as low stock" do
      product = build(:product, stock_quantity: 3)
      expect(product).to be_low_stock
      expect(product).not_to be_out_of_stock
    end

    it "treats a comfortable stock as neither" do
      product = build(:product, stock_quantity: 50)
      expect(product).not_to be_low_stock
      expect(product).not_to be_out_of_stock
    end
  end

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

      expect(Product.sorted("price_desc").to_a).to eq([ pricey, cheap ])
    end

    it "falls back to name ascending for an unknown key" do
      b = create(:product, name: "B Product")
      a = create(:product, name: "A Product")

      expect(Product.sorted("nonsense").to_a).to eq([ a, b ])
    end
  end

  describe ".search" do
    it "stems English words when matching the description (weight B)" do
      product = create(:product, description: "Great for gaming and productivity")

      expect(Product.search("games")).to include(product)
    end

    it "matches brand and model exactly but does not stem them (simple config)" do
      product = create(:product, brand: "Boxes", model: "Prime")

      expect(Product.search("Boxes")).to include(product)
      expect(Product.search("box")).not_to include(product)
    end

    it "matches a SKU case-insensitively even though it contains punctuation" do
      product = create(:product, sku: "SP-001")

      expect(Product.search("sp-001")).to include(product)
    end

    it "matches on a model prefix" do
      nova12 = create(:product, model: "Nova 12")
      nova12pro = create(:product, model: "Nova 12 Pro")
      unrelated = create(:product, model: "Zeta 5")

      results = Product.search("Nova 1").to_a

      expect(results).to include(nova12, nova12pro)
      expect(results).not_to include(unrelated)
    end

    it "matches on a product-name prefix" do
      product = create(:product, name: "Aurora Desk Lamp")

      expect(Product.search("Aurora Desk").to_a).to include(product)
    end

    it "escapes literal wildcard characters instead of treating them as SQL LIKE wildcards" do
      create(:product, model: "ABC123")

      expect(Product.search("%").to_a).to eq([])
      expect(Product.search("_").to_a).to eq([])
    end

    it "ranks an exact SKU match above a plain full-text match" do
      exact_sku = create(:product, sku: "MATCHWORD", name: "Unrelated Name", description: "nothing special")
      full_text_match = create(:product, sku: "OTHER-1", name: "Something", description: "a great matchword item")

      results = Product.search("matchword").to_a

      expect(results.first).to eq(exact_sku)
      expect(results).to include(full_text_match)
    end

    it "ranks an exact name match above a name-prefix match" do
      exact_name = create(:product, name: "SuperWidget")
      prefix_match = create(:product, name: "SuperWidget Deluxe Edition")

      results = Product.search("SuperWidget").to_a

      expect(results.first).to eq(exact_name)
      expect(results).to include(prefix_match)
    end

    it "ranks full-text description matches below name/model/SKU matches" do
      description_only = create(:product, name: "Totally Different", description: "great headphones for travel")
      name_match = create(:product, name: "Headphones Max")

      results = Product.search("headphones").to_a

      expect(results.index(name_match)).to be < results.index(description_only)
    end

    it "breaks ties within the same rank tier by id for stable pagination" do
      first = create(:product, description: "wireless headphones one")
      second = create(:product, description: "wireless headphones two")

      results = Product.search("wireless headphones").to_a

      expect(results.map(&:id)).to eq([ first.id, second.id ].sort)
    end

    it "returns the ordinary, unfiltered catalog for a blank query" do
      create_list(:product, 2)

      expect(Product.search("").to_a).to match_array(Product.all.to_a)
      expect(Product.search("   ").to_a).to match_array(Product.all.to_a)
    end

    it "returns no results, without erroring, for punctuation-only input" do
      create(:product)

      expect(Product.search("!!!").to_a).to eq([])
    end

    it "returns no results, without erroring, for stop-word-only input that matches nothing literally" do
      create(:product, name: "Widget", model: "W1", brand: "Acme")

      expect(Product.search("the").to_a).to eq([])
    end

    it "keeps the search vector current when a product is created or updated" do
      product = create(:product, name: "Alpha Gadget", sku: "AL-1")
      expect(Product.search("Alpha").to_a).to include(product)

      product.update!(name: "Zeta Gadget")

      expect(Product.search("Alpha").to_a).not_to include(product)
      expect(Product.search("Zeta").to_a).to include(product)
    end

    it "populates the generated search_vector column automatically on insert" do
      product = create(:product, name: "Populated Product")

      expect(product.reload.search_vector).to be_present
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
