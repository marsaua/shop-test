class AddSearchVectorToProducts < ActiveRecord::Migration[8.1]
  # `to_tsvector(regconfig, text)` (the two-argument form, with a literal
  # config name) is IMMUTABLE in PostgreSQL - only the one-argument form
  # that reads default_text_search_config is STABLE. That means a stored
  # generated column is allowed here and keeps the vector in sync with no
  # trigger required. Existing rows are backfilled automatically: adding a
  # STORED generated column rewrites the whole table and computes the
  # expression for every row as part of this migration.
  #
  # Weight A: name (english, stemmed) + brand/model (simple, unstemmed so
  # identifiers like "Nova 12" aren't mangled by English stemming/stopwords).
  # Weight B: description (english, stemmed).
  SEARCH_VECTOR_EXPRESSION = <<~SQL.squish
    setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(brand, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(model, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(description, '')), 'B')
  SQL

  def change
    add_column :products, :search_vector, :tsvector, as: SEARCH_VECTOR_EXPRESSION, stored: true

    add_index :products, :search_vector, using: :gin, name: "index_products_on_search_vector"

    # Complementary indexed matching for identifiers that full-text search
    # handles poorly (hyphenated SKUs, exact model/name lookups, prefixes).
    add_index :products, "lower(sku)", name: "index_products_on_lower_sku"
    add_index :products, "lower(model) text_pattern_ops", name: "index_products_on_lower_model_pattern"
    add_index :products, "lower(name) text_pattern_ops", name: "index_products_on_lower_name_pattern"
  end
end
