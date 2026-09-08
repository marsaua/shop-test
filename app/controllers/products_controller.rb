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

  def dollars_to_cents(value)
    return nil if value.blank?

    (value.to_f * 100).round
  end
end
