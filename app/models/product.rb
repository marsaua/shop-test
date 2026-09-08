class Product < ApplicationRecord
  has_one_attached :image

  validates :name, presence: true
  validates :price_cents, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :stock_quantity, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  scope :in_stock, -> { where("stock_quantity > 0") }
  scope :price_gteq, ->(cents) { cents.present? ? where("price_cents >= ?", cents) : all }
  scope :price_lteq, ->(cents) { cents.present? ? where("price_cents <= ?", cents) : all }

  SORT_OPTIONS = {
    "name_asc" => { name: :asc },
    "name_desc" => { name: :desc },
    "price_asc" => { price_cents: :asc },
    "price_desc" => { price_cents: :desc }
  }.freeze

  def self.sorted(key)
    order(SORT_OPTIONS.fetch(key, SORT_OPTIONS["name_asc"]))
  end
end
