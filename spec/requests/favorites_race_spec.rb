require "rails_helper"
require "database_cleaner/active_record"
require_relative "../support/lock_contention"

RSpec.describe "Favorites concurrency", :race_condition, type: :request do
  include LockContention

  self.use_transactional_tests = false

  before { DatabaseCleaner.strategy = :truncation }
  after { DatabaseCleaner.clean }

  it "does not create duplicate favorites when the same product is favorited twice concurrently" do
    user = create(:user)
    product = create(:product)

    session_1 = login_session(user)
    session_2 = login_session(user)

    favorite_job = lambda do |session|
      session.post "/products/#{product.id}/favorite", as: :json
      session.response.status
    end

    statuses = run_under_forced_contention(
      user,
      [ -> { favorite_job.call(session_1) }, -> { favorite_job.call(session_2) } ]
    )

    expect(statuses).to all(eq(201))
    expect(Favorite.where(user_id: user.id, product_id: product.id).count).to eq(1)
  end
end
