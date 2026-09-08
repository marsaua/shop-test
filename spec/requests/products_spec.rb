require "rails_helper"

RSpec.describe "Products", type: :request do
  describe "GET /products" do
    it "is visible to guests" do
      create(:product)
      get products_path
      expect(response).to have_http_status(:ok)
    end

    it "filters to in-stock products only when requested" do
      in_stock = create(:product, name: "In Stock Book", stock_quantity: 3)
      out_of_stock = create(:product, name: "Out Of Stock Book", stock_quantity: 0)

      get products_path(in_stock: "1")

      expect(response.body).to include(in_stock.name)
      expect(response.body).not_to include(out_of_stock.name)
    end

    it "filters by price range" do
      cheap = create(:product, name: "Cheap Book", price_cents: 500)
      pricey = create(:product, name: "Pricey Book", price_cents: 9000)

      get products_path(min_price: "10")

      expect(response.body).to include(pricey.name)
      expect(response.body).not_to include(cheap.name)
    end
  end

  describe "GET /products/:id" do
    it "is visible to guests" do
      product = create(:product)
      get product_path(product)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.name)
    end
  end

  describe "POST /products" do
    let(:params) { { product: { name: "New Book", description: "desc", price_cents: 1200, stock_quantity: 5 } } }

    it "redirects guests to sign in" do
      post products_path, params: params
      expect(response).to redirect_to(new_user_session_path)
    end

    it "is forbidden for regular users" do
      sign_in create(:user)
      post products_path, params: params
      expect(response).to have_http_status(:forbidden)
    end

    it "creates the product for admins" do
      sign_in create(:user, :admin)
      expect { post products_path, params: params }.to change(Product, :count).by(1)
      expect(response).to redirect_to(Product.last)
    end
  end

  describe "PATCH /products/:id" do
    it "lets an admin update stock_quantity" do
      product = create(:product, stock_quantity: 2)
      sign_in create(:user, :admin)

      patch product_path(product), params: { product: { stock_quantity: 50 } }

      expect(product.reload.stock_quantity).to eq(50)
    end

    it "is forbidden for regular users" do
      product = create(:product)
      sign_in create(:user)

      patch product_path(product), params: { product: { stock_quantity: 50 } }

      expect(response).to have_http_status(:forbidden)
      expect(product.reload.stock_quantity).not_to eq(50)
    end
  end

  describe "DELETE /products/:id" do
    it "is forbidden for regular users" do
      product = create(:product)
      sign_in create(:user)

      delete product_path(product)

      expect(response).to have_http_status(:forbidden)
    end

    it "deletes the product for admins" do
      product = create(:product)
      sign_in create(:user, :admin)

      expect { delete product_path(product) }.to change(Product, :count).by(-1)
    end
  end
end
