# Recently-viewed correctness never depends on this running - ProductView's
# within_window/expired scopes filter by last_viewed_at at query time
# regardless. This just keeps the table from growing unboundedly with rows
# no page will ever show again.
class CleanupExpiredProductViewsJob < ApplicationJob
  queue_as :background

  BATCH_SIZE = 1000

  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 5

  # A single cutoff computed once up front, not re-evaluated per batch -
  # otherwise a job that ran across a cutoff boundary could delete a record
  # that was within the window when the run started.
  #
  # Shares ProductView::WINDOW with RefreshProductPopularityStatsJob's
  # aggregation cutoff, rather than a separately-hardcoded duration, so the
  # two can never drift out of sync - popularity stats always stay
  # computable for exactly as long as the underlying history survives.
  def perform
    cutoff = ProductView::WINDOW.ago
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    deleted_count = 0

    # in_batches re-applies the full relation (last_viewed_at < cutoff, plus
    # the id range for the batch) as the WHERE clause of each batch's own
    # DELETE, rather than selecting ids up front and deleting by id - so a
    # row whose last_viewed_at gets refreshed after batching starts but
    # before its batch's DELETE runs is naturally excluded, instead of being
    # deleted on stale information. No model callbacks fire either way:
    # ProductView has none, and deleting the view row never touches the
    # associated product or user rows.
    ProductView.where(last_viewed_at: ...cutoff).in_batches(of: BATCH_SIZE) do |batch|
      deleted_count += batch.delete_all
    end

    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    Rails.logger.info(
      "[CleanupExpiredProductViewsJob] deleted #{deleted_count} expired product view(s) " \
      "in #{duration.round(3)}s (cutoff: #{cutoff.iso8601})"
    )
  end
end
