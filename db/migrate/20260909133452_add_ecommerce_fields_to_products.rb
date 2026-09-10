class AddEcommerceFieldsToProducts < ActiveRecord::Migration[8.1]
  # `category` 5 = "other" is not offered on the new/edit form (see
  # Product::CATEGORY_LABELS) - it exists solely to backfill the pre-existing
  # (non-electronics) demo products below without deleting/recreating them.
  LEGACY_CATEGORY = 5

  def up
    add_column :products, :sku, :string
    add_column :products, :brand, :string
    add_column :products, :model, :string
    add_column :products, :category, :integer
    add_column :products, :previous_price_cents, :integer
    add_column :products, :warranty_months, :integer
    add_column :products, :color, :string
    add_column :products, :weight_grams, :integer
    add_column :products, :specifications, :jsonb, null: false, default: {}

    backfill_legacy_products

    change_column_null :products, :sku, false
    change_column_null :products, :brand, false
    change_column_null :products, :category, false

    add_index :products, :sku, unique: true
    add_index :products, :category
  end

  def down
    remove_index :products, :category
    remove_index :products, :sku

    remove_column :products, :specifications
    remove_column :products, :weight_grams
    remove_column :products, :color
    remove_column :products, :warranty_months
    remove_column :products, :previous_price_cents
    remove_column :products, :category
    remove_column :products, :model
    remove_column :products, :brand
    remove_column :products, :sku
  end

  private

  def backfill_legacy_products
    execute <<~SQL.squish
      UPDATE products
      SET sku = 'LEGACY-' || id,
          brand = 'Unbranded',
          category = #{LEGACY_CATEGORY}
      WHERE sku IS NULL
    SQL
  end
end
