class FavoritesController < ApplicationController
  before_action :authenticate_user!, only: %i[create destroy merge]
  before_action :set_product, only: %i[create destroy]

  def index
    @favorites = user_signed_in? ? current_user.favorites.includes(:product).order(created_at: :desc) : []
  end

  # Locks the current user's row before the find-or-create check, the same
  # way CartItemsController locks the cart, so two concurrent clicks (or a
  # double-submit) on the same product can't both pass the "does this
  # favorite already exist?" check and race past the unique index into a
  # duplicate-row error.
  def create
    ActiveRecord::Base.transaction do
      current_user.lock!
      @favorite = current_user.favorites.find_or_initialize_by(product: @product)
      authorize @favorite
      @favorite.save! unless @favorite.persisted?
    end

    render json: { favorited: true, count: current_user.favorites.count }, status: :created
  end

  def destroy
    @favorite = current_user.favorites.find_by(product: @product)

    if @favorite
      authorize @favorite
      @favorite.destroy!
    end

    render json: { favorited: false, count: current_user.favorites.count }, status: :ok
  end

  def merge
    ids = safe_product_ids(params[:product_ids])

    ActiveRecord::Base.transaction do
      current_user.lock!
      Product.where(id: ids).find_each do |product|
        favorite = current_user.favorites.find_or_initialize_by(product: product)
        favorite.save! unless favorite.persisted?
      end
    end

    render json: {
      count: current_user.favorites.count,
      favorited_product_ids: current_user.favorites.pluck(:product_id)
    }, status: :ok
  end

  private

  def set_product
    @product = Product.find(params[:product_id])
  end

  def safe_product_ids(raw_ids)
    Array(raw_ids).filter_map { |id| Integer(id, exception: false) }.select(&:positive?)
  end
end
