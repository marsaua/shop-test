require "bigdecimal"

class ProductsController < ApplicationController
  before_action :authenticate_user!, only: %i[new create edit update destroy]
  before_action :set_product, only: %i[show edit update destroy]

  def index
    authorize Product
    @products = Product.all
    @products = @products.in_stock if params[:in_stock] == "1"
    @products = @products.price_gteq(dollars_to_cents(params[:min_price]))
    @products = @products.price_lteq(dollars_to_cents(params[:max_price]))
    @products = @products.sorted(params[:sort])
    @products = @products.page(params[:page]).per(12)
  end

  def show
    authorize @product
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

  def product_params
    params.require(:product).permit(:name, :description, :price_cents, :stock_quantity, :image)
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
