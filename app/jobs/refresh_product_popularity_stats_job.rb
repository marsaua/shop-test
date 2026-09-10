# Publishes a fresh "most popular products" snapshot every two hours (see
# config/recurring.yml). The storefront only ever reads what this job wrote
# (ProductPopularityStat.top) - it never aggregates ProductView at request
# time, so a slow or failed run just means the previous snapshot keeps
# serving traffic instead of the homepage failing to load.
class RefreshProductPopularityStatsJob < ApplicationJob
  queue_as :background

  # Solid Queue's own concurrency semaphore - already the project's
  # convention for job-level locking - is what actually prevents two
  # executions of this job from running at once. The calculated_at check in
  # #perform is a second line of defense against a retried/slow run
  # finishing after a fresher one has already published, in case that ever
  # happens regardless.
  limits_concurrency to: 1, key: "RefreshProductPopularityStatsJob", duration: 15.minutes

  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 5

  def perform
    calculated_at = Time.current
    cutoff = calculated_at - ProductView::WINDOW
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # A single GROUP BY/COUNT query against the database - individual
    # ProductView rows are never loaded into Ruby, only one aggregated
    # {product_id => distinct_viewer_count} row per qualifying product.
    counts = ProductView.where(last_viewed_at: cutoff..).group(:product_id).distinct.count(:user_id)

    published = ActiveRecord::Base.transaction do
      # An older calculation (e.g. a slow retry) must never clobber a
      # snapshot a newer run already committed.
      if (latest = ProductPopularityStat.maximum(:calculated_at)) && latest >= calculated_at
        next false
      end

      if counts.any?
        rows = counts.map { |product_id, viewers_count|
          { product_id: product_id, viewers_count: viewers_count, calculated_at: calculated_at }
        }
        # One bulk INSERT ... ON CONFLICT DO UPDATE, not one write per
        # product - and since it's inside this transaction, the whole
        # snapshot becomes visible to readers at COMMIT, never row-by-row.
        ProductPopularityStat.upsert_all(rows, unique_by: :index_product_popularity_stats_on_product_id)
      end

      # Anything still carrying an older calculated_at wasn't touched by the
      # upsert above - it no longer has qualifying views, or its product is
      # gone - so it's stale and is removed here rather than lingering.
      ProductPopularityStat.where(calculated_at: ...calculated_at).delete_all

      true
    end

    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    if published
      Rails.logger.info(
        "[RefreshProductPopularityStatsJob] published #{counts.size} product(s) in #{duration.round(3)}s " \
        "(window: #{ProductView::WINDOW.inspect}, cutoff: #{cutoff.iso8601})"
      )
    else
      Rails.logger.info(
        "[RefreshProductPopularityStatsJob] skipped: a newer snapshot was already published " \
        "(detected in #{duration.round(3)}s)"
      )
    end
  end
end
