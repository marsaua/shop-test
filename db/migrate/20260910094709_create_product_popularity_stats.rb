class CreateProductPopularityStats < ActiveRecord::Migration[8.1]
  # One row per product ("the current result") - the unique index on
  # product_id is both the uniqueness constraint and the upsert_all target
  # RefreshProductPopularityStatsJob writes through.
  def change
    create_table :product_popularity_stats do |t|
      t.references :product, null: false, foreign_key: true, index: { unique: true }
      t.integer :viewers_count, null: false, default: 0
      t.datetime :calculated_at, null: false

      t.timestamps
    end

    # Serves ProductPopularityStat.top's ORDER BY viewers_count DESC, product_id ASC.
    add_index :product_popularity_stats, [ :viewers_count, :product_id ]
  end
end
