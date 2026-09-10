class ProductPopularityStat < ApplicationRecord
  belongs_to :product

  # Reads the snapshot RefreshProductPopularityStatsJob last published -
  # never aggregates ProductView here, so a page load never pays for (or
  # waits on) the GROUP BY/COUNT the job runs every two hours.
  #
  # Visibility is delegated to ProductPolicy::Scope, the same rule the rest
  # of the storefront uses, so this automatically stays in sync if that
  # scope ever grows real restrictions. Joining to products at all also
  # means a stat row whose product no longer exists is excluded here even
  # if it somehow wasn't cleaned up by Product's dependent: :destroy.
  def self.top(user:, limit: 12)
    visible_products = ProductPolicy::Scope.new(user, Product.all).resolve

    joins(:product)
      .merge(visible_products)
      .where("product_popularity_stats.viewers_count > 0")
      .order(viewers_count: :desc, product_id: :asc)
      .limit(limit)
      .preload(product: { image_attachment: :blob })
  end
end
