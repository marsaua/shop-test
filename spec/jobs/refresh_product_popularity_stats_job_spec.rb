require "rails_helper"

RSpec.describe RefreshProductPopularityStatsJob, type: :job do
  BASE_TIME = Time.zone.parse("2026-01-15 12:00:00")

  def stat_for(product)
    ProductPopularityStat.find_by(product: product)
  end

  it "counts distinct users who viewed a product within the window" do
    product = create(:product)
    create(:product_view, product: product, user: create(:user), last_viewed_at: 1.day.ago)
    create(:product_view, product: product, user: create(:user), last_viewed_at: 2.days.ago)

    described_class.perform_now

    expect(stat_for(product).viewers_count).to eq(2)
  end

  it "counts a repeat viewer once" do
    product = create(:product)
    user = create(:user)
    travel_to(BASE_TIME) { ProductView.record!(user: user, product: product) }
    travel_to(BASE_TIME + 1.hour) { ProductView.record!(user: user, product: product) }

    travel_to(BASE_TIME + 1.hour) { described_class.perform_now }

    expect(stat_for(product).viewers_count).to eq(1)
  end

  it "excludes views outside the seven-day window" do
    product = create(:product)
    create(:product_view, product: product, user: create(:user), last_viewed_at: 8.days.ago)

    described_class.perform_now

    expect(stat_for(product)).to be_nil
  end

  it "includes a view exactly at the seven-day boundary" do
    product = create(:product)

    travel_to(BASE_TIME) do
      create(:product_view, product: product, user: create(:user), last_viewed_at: 7.days.ago)
      described_class.perform_now
    end

    expect(stat_for(product)&.viewers_count).to eq(1)
  end

  it "drops a product's popularity once its views age out of the window" do
    product = create(:product)

    travel_to(BASE_TIME) do
      create(:product_view, product: product, user: create(:user), last_viewed_at: Time.current)
      described_class.perform_now
    end
    expect(stat_for(product).viewers_count).to eq(1)

    travel_to(BASE_TIME + 8.days) { described_class.perform_now }

    expect(stat_for(product)).to be_nil
  end

  it "orders products deterministically when viewer counts tie" do
    tie_a = create(:product)
    tie_b = create(:product)
    create(:product_view, product: tie_a, user: create(:user), last_viewed_at: 1.day.ago)
    create(:product_view, product: tie_b, user: create(:user), last_viewed_at: 1.day.ago)

    described_class.perform_now

    expected_order = [ tie_a, tie_b ].sort_by(&:id)
    expect(ProductPopularityStat.top(user: nil).map(&:product)).to eq(expected_order)
  end

  it "does not create duplicate stat rows when run repeatedly" do
    product = create(:product)
    create(:product_view, product: product, user: create(:user), last_viewed_at: 1.day.ago)

    described_class.perform_now
    described_class.perform_now

    expect(ProductPopularityStat.where(product: product).count).to eq(1)
  end

  it "removes stats for products with no qualifying views left, without touching still-qualifying ones" do
    fading = create(:product)
    staying = create(:product)

    travel_to(BASE_TIME) do
      create(:product_view, product: fading, user: create(:user), last_viewed_at: Time.current)
      create(:product_view, product: staying, user: create(:user), last_viewed_at: Time.current)
      described_class.perform_now
    end
    expect(ProductPopularityStat.pluck(:product_id)).to contain_exactly(fading.id, staying.id)

    travel_to(BASE_TIME + 8.days) do
      create(:product_view, product: staying, user: create(:user), last_viewed_at: Time.current)
      described_class.perform_now
    end

    expect(ProductPopularityStat.pluck(:product_id)).to contain_exactly(staying.id)
  end

  it "leaves the previous completed snapshot untouched when persistence fails" do
    kept = create(:product)
    create(:product_view, product: kept, user: create(:user), last_viewed_at: 1.day.ago)
    described_class.perform_now
    previous_snapshot = ProductPopularityStat.pluck(:product_id, :viewers_count, :calculated_at)

    new_product = create(:product)
    create(:product_view, product: new_product, user: create(:user), last_viewed_at: 1.day.ago)
    allow(ProductPopularityStat).to receive(:upsert_all).and_raise(ActiveRecord::StatementInvalid, "boom")

    travel(1.hour) do
      expect { described_class.perform_now }.to raise_error(ActiveRecord::StatementInvalid)
    end

    expect(ProductPopularityStat.pluck(:product_id, :viewers_count, :calculated_at)).to eq(previous_snapshot)
  end

  it "does not let an older calculation overwrite a newer published snapshot" do
    product = create(:product)
    create(:product_view, product: product, user: create(:user), last_viewed_at: 1.day.ago)

    newer_time = BASE_TIME + 1.hour
    travel_to(newer_time) { described_class.perform_now }
    newer_snapshot = ProductPopularityStat.pluck(:product_id, :viewers_count, :calculated_at)

    # Simulate a slow/retried execution that started earlier but is only
    # persisting now, after the newer run above already published.
    travel_to(newer_time - 30.minutes) { described_class.perform_now }

    expect(ProductPopularityStat.pluck(:product_id, :viewers_count, :calculated_at)).to eq(newer_snapshot)
  end

  it "completes successfully when there is no viewing history" do
    expect { described_class.perform_now }.not_to raise_error
    expect(ProductPopularityStat.count).to eq(0)
  end

  it "aggregates with database GROUP BY/COUNT rather than loading individual ProductView records into Ruby" do
    product = create(:product)
    create(:product_view, product: product, user: create(:user), last_viewed_at: 1.day.ago)

    expect(ProductView).not_to receive(:find_each)
    expect(ProductView).not_to receive(:find_in_batches)

    described_class.perform_now
  end

  it "logs the number of products processed and duration without user identities" do
    user = create(:user)
    product = create(:product)
    create(:product_view, product: product, user: user, last_viewed_at: 1.day.ago)
    logged_messages = []
    allow(Rails.logger).to receive(:info) { |message| logged_messages << message }

    described_class.perform_now

    expect(logged_messages).to include(a_string_matching(/published 1 product\(s\) in [\d.]+s/))
    expect(logged_messages.join).not_to include(user.email)
  end

  it "stays compatible with CleanupExpiredProductViewsJob: a view still countable here has not yet been cleaned up" do
    product = create(:product)

    travel_to(BASE_TIME) do
      create(:product_view, product: product, user: create(:user), last_viewed_at: 7.days.ago)
      CleanupExpiredProductViewsJob.perform_now
      described_class.perform_now
    end

    expect(ProductView.where(product: product)).to exist
    expect(stat_for(product)&.viewers_count).to eq(1)
  end
end
