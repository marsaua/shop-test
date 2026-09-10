class ProductViewsController < ApplicationController
  PER_PAGE = 12

  before_action :authenticate_user!
  before_action :set_product, only: :create

  # A DB hiccup while loading the list is the only failure mode worth a
  # dedicated state here (everything else - ownership, the 7-day window -
  # is enforced in the query itself); render the same page with a retry
  # link instead of the generic 500 page.
  rescue_from ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished, with: :render_load_error

  def index
    @product_views = current_user.product_views
      .within_window
      .includes(:product)
      .order(last_viewed_at: :desc, id: :desc)
      .page(params[:page]).per(PER_PAGE)
    @favorited_product_ids = favorited_product_ids
  end

  # Records that the current user just viewed @product. Identity comes
  # entirely from the authenticated session (current_user), never from any
  # client-supplied id. Idempotent and safe under concurrent requests - see
  # ProductView.record!.
  def create
    @product_view = current_user.product_views.new(product: @product)
    authorize @product_view

    ProductView.record!(user: current_user, product: @product)

    head :no_content
  end

  private

  def set_product
    @product = Product.find(params[:product_id])
    authorize @product, :show?
  end

  def favorited_product_ids
    current_user.favorites.pluck(:product_id).to_set
  end

  def render_load_error
    @load_error = true
    @product_views = ProductView.none.page(params[:page]).per(PER_PAGE)
    @favorited_product_ids = Set.new
    render :index, status: :internal_server_error
  end
end
