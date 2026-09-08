class CartItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_cart_item, only: %i[update destroy]

  def create
    @cart_item = current_user.cart.cart_items.find_or_initialize_by(product_id: params[:product_id])
    authorize @cart_item

    current_quantity = @cart_item.persisted? ? @cart_item.quantity : 0
    @cart_item.quantity = current_quantity + quantity_param

    if @cart_item.save
      redirect_to cart_path, notice: "Added to cart."
    else
      redirect_to product_path(params[:product_id]), alert: @cart_item.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @cart_item
    if @cart_item.update(quantity: quantity_param)
      redirect_to cart_path, notice: "Cart updated."
    else
      redirect_to cart_path, alert: @cart_item.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @cart_item
    @cart_item.destroy
    redirect_to cart_path, notice: "Removed from cart."
  end

  private

  def set_cart_item
    @cart_item = CartItem.find(params[:id])
  end

  def quantity_param
    params[:quantity].to_i.clamp(1, 1000)
  end
end
