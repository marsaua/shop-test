class CreateProductViews < ActiveRecord::Migration[8.1]
  def change
    create_table :product_views do |t|
      t.references :user, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.datetime :last_viewed_at, null: false

      t.timestamps
    end

    add_index :product_views, [ :user_id, :product_id ], unique: true
    # Serves "this user's views, newest first" (ProductView.within_window,
    # ordered by last_viewed_at desc) without a sort - the query this table
    # exists for.
    add_index :product_views, [ :user_id, :last_viewed_at ]
  end
end
