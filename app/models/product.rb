class Product < ApplicationRecord
  has_one_attached :image
  has_many :cart_items, dependent: :destroy
  has_many :order_items, dependent: :restrict_with_error
  has_many :favorites, dependent: :destroy
  has_many :product_views, dependent: :destroy
  has_one :product_popularity_stat, dependent: :destroy

  # `other` exists only to backfill pre-existing, non-electronics demo
  # products introduced before this catalog was themed around electronics
  # (see the AddEcommerceFieldsToProducts migration) - it is intentionally
  # left out of CATEGORY_LABELS so it never appears as a choice on the form.
  enum :category, {
    smartphones: 0,
    laptops: 1,
    tvs_and_monitors: 2,
    headphones: 3,
    accessories: 4,
    other: 5
  }

  CATEGORY_LABELS = {
    "smartphones" => "Smartphones",
    "laptops" => "Laptops",
    "tvs_and_monitors" => "TVs & Monitors",
    "headphones" => "Headphones",
    "accessories" => "Accessories"
  }.freeze

  LOW_STOCK_THRESHOLD = 5

  SPECIFICATION_LABEL_OVERRIDES = {
    "ram" => "RAM", "ssd" => "SSD", "os" => "OS", "anc" => "ANC",
    "gb" => "GB", "mah" => "mAh", "hz" => "Hz", "w" => "W"
  }.freeze

  validates :name, presence: true
  validates :price_cents, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :stock_quantity, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :sku, presence: true, uniqueness: true
  validates :brand, presence: true
  validates :category, presence: true
  validates :warranty_months, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :weight_grams, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :previous_price_cents, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validate :previous_price_must_exceed_price
  validate :specifications_must_be_a_hash

  scope :in_stock, -> { where("stock_quantity > 0") }
  scope :price_gteq, ->(cents) { cents.present? ? where("price_cents >= ?", cents) : all }
  scope :price_lteq, ->(cents) { cents.present? ? where("price_cents <= ?", cents) : all }

  SORT_OPTIONS = {
    "name_asc" => { name: :asc },
    "name_desc" => { name: :desc },
    "price_asc" => { price_cents: :asc },
    "price_desc" => { price_cents: :desc }
  }.freeze

  MAX_SEARCH_QUERY_LENGTH = 200

  # Ranks matches into tiers (exact SKU, then exact name/model, then
  # prefix matches, then plain full-text matches) and breaks ties within
  # a tier by ts_rank_cd, then id for a stable sort under pagination.
  #
  # websearch_to_tsquery never raises on malformed/punctuation-only/
  # stop-word-only input - it just produces an empty tsquery, which
  # matches nothing via `@@`. That keeps blank-ish queries predictable
  # (zero rows) instead of erroring or silently returning everything.
  #
  # model/name prefix matching intentionally runs against the raw
  # (unstemmed, untokenized) column via `lower(...) LIKE lower(prefix)`
  # rather than through the tsvector, since a full-text index can't do
  # arbitrary prefix/substring matching and tokenization would split
  # punctuated identifiers unpredictably. Wildcard characters in the
  # user's query are escaped so they can't be used to inject `%`/`_`.
  scope :search, ->(raw_query) {
    query = raw_query.to_s.strip.first(MAX_SEARCH_QUERY_LENGTH)
    next all if query.blank?

    prefix_pattern = "#{sanitize_sql_like(query)}%"

    relation = select(
      sanitize_sql_array([
        <<~SQL.squish,
          products.*,
          CASE
            WHEN lower(products.sku) = lower(:term) THEN 0
            WHEN lower(products.model) = lower(:term) OR lower(products.name) = lower(:term) THEN 1
            WHEN lower(products.model) LIKE lower(:prefix) ESCAPE '\\' OR lower(products.name) LIKE lower(:prefix) ESCAPE '\\' THEN 2
            ELSE 3
          END AS search_rank_tier,
          ts_rank_cd(
            products.search_vector,
            (websearch_to_tsquery('english', :term) || websearch_to_tsquery('simple', :term))
          ) AS search_rank_score
        SQL
        { term: query, prefix: prefix_pattern }
      ])
    ).where(
      sanitize_sql_array([
        <<~SQL.squish,
          products.search_vector @@ (websearch_to_tsquery('english', :term) || websearch_to_tsquery('simple', :term))
          OR lower(products.sku) = lower(:term)
          OR lower(products.model) LIKE lower(:prefix) ESCAPE '\\'
          OR lower(products.name) LIKE lower(:prefix) ESCAPE '\\'
        SQL
        { term: query, prefix: prefix_pattern }
      ])
    )

    relation.order(Arel.sql("search_rank_tier ASC, search_rank_score DESC, products.id ASC"))
  }

  def self.sorted(key)
    reorder(SORT_OPTIONS.fetch(key, SORT_OPTIONS["name_asc"]))
  end

  def category_label
    CATEGORY_LABELS.fetch(category, category&.humanize)
  end

  def specification_label(key)
    SPECIFICATION_LABEL_OVERRIDES.reduce(key.humanize) do |label, (token, replacement)|
      label.gsub(/\b#{token}\b/i, replacement)
    end
  end

  def discounted?
    previous_price_cents.present? && previous_price_cents > price_cents
  end

  def low_stock?
    stock_quantity.positive? && stock_quantity <= LOW_STOCK_THRESHOLD
  end

  def out_of_stock?
    stock_quantity <= 0
  end

  # The admin form submits specifications as a raw JSON string (there's no
  # per-category structured input); parse it here so assignment behaves the
  # same whether callers pass a Hash (seeds, tests) or a JSON String (form).
  def specifications=(value)
    if value.is_a?(String)
      value = value.strip
      value = value.empty? ? {} : (JSON.parse(value) rescue nil)
    end
    super(value)
  end

  private

  def previous_price_must_exceed_price
    return if previous_price_cents.blank? || price_cents.blank?

    errors.add(:previous_price_cents, "must be greater than the current price") if previous_price_cents <= price_cents
  end

  def specifications_must_be_a_hash
    errors.add(:specifications, "must be valid JSON") unless specifications.is_a?(Hash)
  end
end
