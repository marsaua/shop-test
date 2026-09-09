class CheckoutsController < ApplicationController
  before_action :authenticate_user!

  def new
  end

  def create
    result = CheckoutService.new(user: current_user, card_number: params[:card_number]).call

    if result.success?
      redirect_to order_path(result.order), notice: "Payment successful."
    elsif result.order
      redirect_to order_path(result.order), alert: failure_message(result.error)
    else
      redirect_to new_checkout_path, alert: failure_message(result.error)
    end
  end

  private

  def failure_message(error)
    case error
    when "invalid_card" then "That card number is not valid."
    when "insufficient_funds" then "That card does not have enough balance."
    when "empty_cart" then "Your cart is empty."
    when "out_of_stock" then "One or more items in your cart are out of stock."
    else "Checkout could not be completed."
    end
  end
end
