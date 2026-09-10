# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_10_094709) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata", default: "{}"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "cart_items", force: :cascade do |t|
    t.bigint "cart_id", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["cart_id", "product_id"], name: "index_cart_items_on_cart_id_and_product_id", unique: true
    t.index ["cart_id"], name: "index_cart_items_on_cart_id"
    t.index ["product_id"], name: "index_cart_items_on_product_id"
  end

  create_table "carts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_carts_on_user_id", unique: true
  end

  create_table "favorites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["product_id"], name: "index_favorites_on_product_id"
    t.index ["user_id", "product_id"], name: "index_favorites_on_user_id_and_product_id", unique: true
    t.index ["user_id"], name: "index_favorites_on_user_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.string "product_name", null: false
    t.integer "quantity", null: false
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "card_last4"
    t.datetime "created_at", null: false
    t.string "failure_reason"
    t.integer "status", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "payment_cards", force: :cascade do |t|
    t.integer "balance_cents", default: 0, null: false
    t.string "card_number", null: false
    t.datetime "created_at", null: false
    t.string "holder_name"
    t.datetime "updated_at", null: false
    t.index ["card_number"], name: "index_payment_cards_on_card_number", unique: true
  end

  create_table "product_popularity_stats", force: :cascade do |t|
    t.datetime "calculated_at", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.integer "viewers_count", default: 0, null: false
    t.index ["product_id"], name: "index_product_popularity_stats_on_product_id", unique: true
    t.index ["viewers_count", "product_id"], name: "index_product_popularity_stats_on_viewers_count_and_product_id"
  end

  create_table "product_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_viewed_at", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["last_viewed_at"], name: "index_product_views_on_last_viewed_at"
    t.index ["product_id"], name: "index_product_views_on_product_id"
    t.index ["user_id", "last_viewed_at"], name: "index_product_views_on_user_id_and_last_viewed_at"
    t.index ["user_id", "product_id"], name: "index_product_views_on_user_id_and_product_id", unique: true
    t.index ["user_id"], name: "index_product_views_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "brand", null: false
    t.integer "category", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "model"
    t.string "name", null: false
    t.integer "previous_price_cents"
    t.integer "price_cents", null: false
    t.virtual "search_vector", type: :tsvector, as: "(((setweight(to_tsvector('english'::regconfig, (COALESCE(name, ''::character varying))::text), 'A'::\"char\") || setweight(to_tsvector('simple'::regconfig, (COALESCE(brand, ''::character varying))::text), 'A'::\"char\")) || setweight(to_tsvector('simple'::regconfig, (COALESCE(model, ''::character varying))::text), 'A'::\"char\")) || setweight(to_tsvector('english'::regconfig, COALESCE(description, ''::text)), 'B'::\"char\"))", stored: true
    t.string "sku", null: false
    t.jsonb "specifications", default: {}, null: false
    t.integer "stock_quantity", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "warranty_months"
    t.integer "weight_grams"
    t.index "lower((model)::text) text_pattern_ops", name: "index_products_on_lower_model_pattern"
    t.index "lower((name)::text) text_pattern_ops", name: "index_products_on_lower_name_pattern"
    t.index "lower((sku)::text)", name: "index_products_on_lower_sku"
    t.index ["category"], name: "index_products_on_category"
    t.index ["search_vector"], name: "index_products_on_search_vector", using: :gin
    t.index ["sku"], name: "index_products_on_sku", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "cart_items", "carts"
  add_foreign_key "cart_items", "products"
  add_foreign_key "carts", "users"
  add_foreign_key "favorites", "products"
  add_foreign_key "favorites", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "users"
  add_foreign_key "product_popularity_stats", "products"
  add_foreign_key "product_views", "products"
  add_foreign_key "product_views", "users"
end
