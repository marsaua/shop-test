require "bigdecimal"

class ProductsController < ApplicationController
  before_action :authenticate_user!, only: %i[new create edit update destroy]
  before_action :set_product, only: %i[show edit update destroy]

  def index
    authorize Product
    @query = params[:q].to_s.strip.first(Product::MAX_SEARCH_QUERY_LENGTH)
    @products = Product.all
    @products = @products.search(@query) if @query.present?
    @products = @products.in_stock if params[:in_stock] == "1"
    @products = @products.price_gteq(dollars_to_cents(params[:min_price]))
    @products = @products.price_lteq(dollars_to_cents(params[:max_price]))
    # Relevance is the default order once a query narrows the results; an
    # explicit sort choice overrides it. Without a query, behavior is
    # unchanged from before search existed.
    @products = @products.sorted(params[:sort]) if params[:sort].present? || @query.blank?
    @products = @products.page(params[:page]).per(12)
    @favorited_product_ids = favorited_product_ids
  end

  def show
    authorize @product
    @favorited_product_ids = favorited_product_ids
  end

  def by_ids
    authorize Product, :index?
    ids = Array(params[:ids]).filter_map { |id| Integer(id, exception: false) }
    products = Product.where(id: ids)

    render json: products.map { |product|
      {
        id: product.id,
        name: product.name,
        price_cents: product.price_cents,
        in_stock: product.stock_quantity > 0,
        image_url: product.image.attached? ? url_for(product.image) : nil,
        brand: product.brand,
        model: product.model,
        category: product.category,
        category_label: product.category_label,
        previous_price_cents: product.previous_price_cents,
        discounted: product.discounted?,
        stock_quantity: product.stock_quantity,
        low_stock: product.low_stock?,
        out_of_stock: product.out_of_stock?,
        warranty_months: product.warranty_months,
        specifications: product.specifications
      }
    }
  end

  def new
    @product = authorize Product.new
  end

  def create
    @product = authorize Product.new(product_params)
    if @product.save
      redirect_to @product, notice: "Product created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @product
  end

  def update
    authorize @product
    if @product.update(product_params)
      redirect_to @product, notice: "Product updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @product
    if @product.destroy
      redirect_to products_path, notice: "Product deleted."
    else
      redirect_to products_path, alert: @product.errors.full_messages.to_sentence
    end
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def favorited_product_ids
    user_signed_in? ? current_user.favorites.pluck(:product_id).to_set : Set.new
  end

  def product_params
    params.require(:product).permit(
      :name, :description, :price_cents, :stock_quantity, :image,
      :sku, :brand, :model, :category, :previous_price_cents,
      :warranty_months, :color, :weight_grams, :specifications
    )
  end

  # Strict, safe dollars->cents parsing for public query params. Only a
  # plain non-negative decimal string (no scientific notation, no
  # array/hash-shaped params) is accepted; anything else is treated as
  # "no filter" rather than raising, since min_price/max_price come
  # straight from unauthenticated query params. Uses BigDecimal so we
  # never do money math in floats.
  def dollars_to_cents(value)
    return nil unless value.is_a?(String)

    sanitized = value.strip
    return nil unless sanitized.match?(/\A\d+(\.\d+)?\z/)

    (BigDecimal(sanitized) * 100).round.to_i
  rescue ArgumentError
    nil
  end
end
