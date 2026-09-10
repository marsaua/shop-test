class ProductView < ApplicationRecord
  belongs_to :user
  belongs_to :product

  validates :product_id, uniqueness: { scope: :user_id }
  validates :last_viewed_at, presence: true

  WINDOW = 7.days

  scope :within_window, -> { where(last_viewed_at: WINDOW.ago..) }
  scope :expired, -> { where(last_viewed_at: ...WINDOW.ago) }

  # Atomically records (or refreshes) that `user` viewed `product`, via a
  # real INSERT ... ON CONFLICT DO UPDATE - unlike Favorite, which
  # serializes concurrent writes with a row lock (see
  # FavoritesController#create), two requests racing to record the same
  # user/product pair here can't both pass a find-or-create check into a
  # duplicate row, because there's no such check: the database's own unique
  # index resolves the conflict.
  #
  # `update_only: :last_viewed_at` keeps `created_at` (first-ever view) from
  # being overwritten on conflict; `updated_at` still refreshes automatically
  # since Rails always touches it for a changed row.
  def self.record!(user:, product:)
    upsert(
      { user_id: user.id, product_id: product.id, last_viewed_at: Time.current },
      unique_by: :index_product_views_on_user_id_and_product_id,
      update_only: :last_viewed_at
    )
  end
end
