require "rails_helper"

RSpec.describe CleanupExpiredProductViewsJob, type: :job do
  around do |example|
    travel_to(Time.zone.parse("2026-01-15 12:00:00")) { example.run }
  end

  it "deletes product views whose last_viewed_at is older than one week" do
    old = create(:product_view, last_viewed_at: 1.week.ago - 1.second)

    described_class.perform_now

    expect(ProductView.exists?(old.id)).to be false
  end

  it "retains product views whose last_viewed_at is within one week" do
    recent = create(:product_view, last_viewed_at: 1.day.ago)

    described_class.perform_now

    expect(ProductView.exists?(recent.id)).to be true
  end

  it "retains a product view whose last_viewed_at is exactly at the cutoff" do
    boundary = create(:product_view, last_viewed_at: 1.week.ago)

    described_class.perform_now

    expect(ProductView.exists?(boundary.id)).to be true
  end

  it "retains a record created long ago but viewed recently" do
    view = create(:product_view, last_viewed_at: 1.day.ago)
    view.update_column(:created_at, 1.year.ago)

    described_class.perform_now

    expect(ProductView.exists?(view.id)).to be true
  end

  it "never deletes the associated product or user" do
    old = create(:product_view, last_viewed_at: 1.week.ago - 1.second)
    product = old.product
    user = old.user

    described_class.perform_now

    expect(Product.exists?(product.id)).to be true
    expect(User.exists?(user.id)).to be true
  end

  it "completes successfully when there is no history to clean up" do
    expect { described_class.perform_now }.not_to raise_error
  end

  it "is safe to run repeatedly" do
    create(:product_view, last_viewed_at: 1.week.ago - 1.second)
    create(:product_view, last_viewed_at: 1.day.ago)

    described_class.perform_now

    expect {
      described_class.perform_now
    }.not_to change { ProductView.count }
  end

  it "processes deletions in batches rather than a single query" do
    create_list(:product_view, 3, last_viewed_at: 1.week.ago - 1.second)
    stub_const("CleanupExpiredProductViewsJob::BATCH_SIZE", 1)

    delete_statements = 0
    callback = lambda do |*, payload|
      delete_statements += 1 if payload[:sql]&.start_with?("DELETE")
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      described_class.perform_now
    end

    expect(delete_statements).to eq(3)
    expect(ProductView.count).to eq(0)
  end

  it "logs the number of deleted records and duration without personal data" do
    old = create(:product_view, last_viewed_at: 1.week.ago - 1.second)
    logged_messages = []
    allow(Rails.logger).to receive(:info) { |message| logged_messages << message }

    described_class.perform_now

    expect(logged_messages).to include(a_string_matching(/deleted 1 expired product view.*in [\d.]+s/))
    expect(logged_messages.join).not_to include(old.user.email)
  end
end
