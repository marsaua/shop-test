require "rails_helper"
require "database_cleaner/active_record"

RSpec.describe ProductView, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:product) }

  it "does not allow the same product to be recorded twice for the same user" do
    user = create(:user)
    product = create(:product)
    create(:product_view, user: user, product: product)

    duplicate = build(:product_view, user: user, product: product)

    expect(duplicate).not_to be_valid
  end

  it "allows different users to have viewed the same product" do
    product = create(:product)
    create(:product_view, user: create(:user), product: product)

    other = build(:product_view, user: create(:user), product: product)

    expect(other).to be_valid
  end

  describe ".within_window / .expired" do
    it "splits records by the 7-day cutoff" do
      travel_to Time.zone.parse("2026-01-15 12:00:00") do
        user = create(:user)
        recent = create(:product_view, user: user, product: create(:product), last_viewed_at: 1.day.ago)
        boundary = create(:product_view, user: user, product: create(:product), last_viewed_at: ProductView::WINDOW.ago)
        old = create(:product_view, user: user, product: create(:product), last_viewed_at: ProductView::WINDOW.ago - 1.second)

        expect(ProductView.within_window).to contain_exactly(recent, boundary)
        expect(ProductView.expired).to contain_exactly(old)
      end
    end
  end

  describe ".record!" do
    it "creates a row on the first view" do
      user = create(:user)
      product = create(:product)

      expect {
        ProductView.record!(user: user, product: product)
      }.to change { ProductView.count }.by(1)

      view = ProductView.find_by(user: user, product: product)
      expect(view.last_viewed_at).to be_present
    end

    it "updates last_viewed_at without creating a duplicate row on a revisit" do
      user = create(:user)
      product = create(:product)
      ProductView.record!(user: user, product: product)
      view = ProductView.find_by(user: user, product: product)
      original_created_at = view.created_at

      travel 1.hour do
        expect {
          ProductView.record!(user: user, product: product)
        }.not_to change { ProductView.count }

        view.reload
        expect(view.last_viewed_at).to be_within(1.second).of(Time.current)
        expect(view.created_at).to be_within(1.second).of(original_created_at)
      end
    end

    it "scopes views independently per user" do
      product = create(:product)
      user_a = create(:user)
      user_b = create(:user)

      ProductView.record!(user: user_a, product: product)
      ProductView.record!(user: user_b, product: product)

      expect(ProductView.where(product: product).count).to eq(2)
    end
  end

  describe "concurrent writes", :race_condition do
    self.use_transactional_tests = false

    before { DatabaseCleaner.strategy = :truncation }
    after { DatabaseCleaner.clean }

    it "preserves uniqueness when the same user/product pair is recorded concurrently" do
      user = create(:user)
      product = create(:product)

      threads = Array.new(8) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ProductView.record!(user: user, product: product)
          end
        end
      end
      threads.each { |t| t.join(5) }

      expect(threads).to all(satisfy { |t| !t.alive? })
      expect(ProductView.where(user: user, product: product).count).to eq(1)
    end
  end
end
