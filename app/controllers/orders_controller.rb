class OrdersController < ApplicationController
  before_action :authenticate_user!

  def index
    @orders = policy_scope(Order).order(created_at: :desc)
  end

  def show
    @order = Order.find(params[:id])
    authorize @order
  end
end
