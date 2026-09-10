# Recently-viewed correctness never depends on this running - ProductView's
# within_window/expired scopes filter by last_viewed_at at query time
# regardless. This just keeps the table from growing unboundedly with rows
# no page will ever show again.
class CleanupExpiredProductViewsJob < ApplicationJob
  queue_as :background

  def perform
    ProductView.expired.in_batches.delete_all
  end
end
