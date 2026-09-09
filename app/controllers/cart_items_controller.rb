class CartItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_cart_item, only: %i[update destroy]

  # Every mutation below takes the same row lock CheckoutService takes on
  # the cart (cart first, same lock order as checkout — see
  # docs/superpowers/specs/2026-09-08-online-store-design.md) so a cart
  # mutation can never interleave with a checkout that's reading/clearing
  # the same cart. For update/destroy, the record is re-fetched *after*
  # the lock is granted, since checkout may have deleted it (via
  # cart.cart_items.destroy_all) while this request was waiting for the
  # lock — mutating the pre-lock in-memory instance would silently no-op
  # against a row that's already gone.

  def create
    quantity = quantity_param
    cart = current_user.cart

    ActiveRecord::Base.transaction do
      cart.lock!
      @cart_item = cart.cart_items.find_or_initialize_by(product_id: params[:product_id])
      authorize @cart_item

      current_quantity = @cart_item.persisted? ? @cart_item.quantity : 0
      @cart_item.quantity = current_quantity + quantity
      @cart_item.save!
    end

    redirect_to cart_path, notice: "Added to cart."
  rescue ActiveRecord::RecordInvalid
    redirect_to product_path(params[:product_id]), alert: @cart_item.errors.full_messages.to_sentence
  end

  def update
    authorize @cart_item
    quantity = quantity_param

    ActiveRecord::Base.transaction do
      cart = @cart_item.cart
      cart.lock!
      @cart_item = cart.cart_items.find_by(id: @cart_item.id)
      @cart_item&.update!(quantity: quantity)
    end

    if @cart_item.nil?
      redirect_to cart_path, alert: "That item is no longer in your cart."
    else
      redirect_to cart_path, notice: "Cart updated."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to cart_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    authorize @cart_item

    ActiveRecord::Base.transaction do
      cart = @cart_item.cart
      cart.lock!
      fresh_item = cart.cart_items.find_by(id: @cart_item.id)
      fresh_item&.destroy!
    end

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
