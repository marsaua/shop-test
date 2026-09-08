require "rails_helper"

RSpec.describe "Orders", type: :request do
  it "requires sign in" do
    get orders_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "only lists the current user's own orders" do
    user = create(:user)
    other = create(:user)
    mine = create(:order, user: user)
    create(:order, user: other)
    sign_in user

    get orders_path

    expect(response.body).to include("##{mine.id}")
  end

  it "lets an admin see every order in the index" do
    admin = create(:user, :admin)
    order_a = create(:order)
    order_b = create(:order)
    sign_in admin

    get orders_path

    expect(response.body).to include("##{order_a.id}")
    expect(response.body).to include("##{order_b.id}")
  end

  it "lets the owner view their own order" do
    user = create(:user)
    order = create(:order, user: user)
    sign_in user

    get order_path(order)

    expect(response).to have_http_status(:ok)
  end

  it "forbids viewing another user's order" do
    order = create(:order)
    sign_in create(:user)

    get order_path(order)

    expect(response).to have_http_status(:forbidden)
  end

  it "lets an admin view any order" do
    order = create(:order)
    sign_in create(:user, :admin)

    get order_path(order)

    expect(response).to have_http_status(:ok)
  end
end
