class AddIndexOnLastViewedAtToProductViews < ActiveRecord::Migration[8.1]
  # The existing (user_id, last_viewed_at) index serves "this user's views,
  # newest first" but can't help CleanupExpiredProductViewsJob's scan, which
  # has no user_id filter - it needs last_viewed_at indexed on its own.
  def change
    add_index :product_views, :last_viewed_at
  end
end
