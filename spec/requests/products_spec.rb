require "rails_helper"

RSpec.describe "Products", type: :request do
  describe "GET /products" do
    it "is visible to guests" do
      create(:product)
      get products_path
      expect(response).to have_http_status(:ok)
    end

    it "makes each product card's links break out of the products-results turbo frame" do
      product = create(:product, name: "Frame Breakout Widget")

      get products_path

      card = response.body[/<article class="product-card" data-product-id="#{product.id}">.*?<\/article>/m]
      expect(card).to include(%(data-turbo-frame="_top" href="#{product_path(product)}"))
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

    it "filters by a decimal price value" do
      cheap = create(:product, name: "Cheap Book", price_cents: 999)
      pricey = create(:product, name: "Pricey Book", price_cents: 1500)

      get products_path(min_price: "10.50")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(pricey.name)
      expect(response.body).not_to include(cheap.name)
    end

    it "treats arbitrary text as no filter instead of erroring" do
      product = create(:product)

      get products_path(min_price: "not-a-number")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.name)
    end

    it "treats a huge exponent as no filter instead of erroring" do
      product = create(:product)

      get products_path(min_price: "1e309")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.name)
    end

    it "treats an array-shaped price param as no filter instead of erroring" do
      product = create(:product)

      get products_path(min_price: [ "10" ])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.name)
    end

    it "treats a hash-shaped price param as no filter instead of erroring" do
      product = create(:product)

      get products_path(min_price: { sneaky: "10" })

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.name)
    end

    it "treats a negative price value as no filter instead of erroring" do
      product = create(:product)

      get products_path(min_price: "-10")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.name)
    end

    it "handles malformed min_price and max_price together without erroring" do
      product = create(:product)

      get products_path(min_price: "1e309", max_price: { sneaky: "1" })

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.name)
    end
  end

  describe "GET /products with a search query" do
    it "finds products by name, brand, model, or SKU" do
      match = create(:product, name: "Voltrix Nova 12", brand: "Voltrix", model: "Nova 12")
      other = create(:product, name: "Something Else Entirely")

      get products_path(q: "Voltrix")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(match.name)
      expect(response.body).not_to include(other.name)
    end

    it "matches a SKU containing punctuation, case-insensitively" do
      match = create(:product, sku: "SP-001", name: "Some Phone")

      get products_path(q: "sp-001")

      expect(response.body).to include(match.name)
    end

    it "trims surrounding whitespace from the query" do
      match = create(:product, name: "Trimmed Match")

      get products_path(q: "  Trimmed Match  ")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(match.name)
    end

    it "shows a no-results message instead of an empty or unfiltered list" do
      create(:product, name: "Anything")

      get products_path(q: "zzzznonexistentzzzz")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No products match")
      expect(response.body).not_to include("Anything")
    end

    it "does not error and does not return an unfiltered catalog for punctuation-only input" do
      create(:product, name: "Should Not Appear")

      get products_path(q: "!!!")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Should Not Appear")
    end

    it "keeps ordinary catalog behavior when the query is blank" do
      product = create(:product)

      get products_path(q: "")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.name)
    end

    it "combines search with the existing in-stock and price filters" do
      match = create(:product, name: "Combo Widget", stock_quantity: 5, price_cents: 2000)
      out_of_stock = create(:product, name: "Combo Widget Out Of Stock", stock_quantity: 0, price_cents: 2000)
      too_expensive = create(:product, name: "Combo Widget Expensive", stock_quantity: 5, price_cents: 90_00)

      get products_path(q: "Combo Widget", in_stock: "1", max_price: "50")

      expect(response.body).to include(match.name)
      expect(response.body).not_to include(out_of_stock.name)
      expect(response.body).not_to include(too_expensive.name)
    end

    it "orders by relevance by default when a query is present" do
      exact = create(:product, name: "Relevance Match")
      prefix = create(:product, name: "Relevance Match Extended")

      get products_path(q: "Relevance Match")

      body = response.body
      expect(body.index(exact.name)).to be < body.index(prefix.name)
    end

    it "lets an explicit sort override relevance ordering while still filtering by the query" do
      cheap = create(:product, name: "Sortable Match Cheap", price_cents: 1000)
      pricey = create(:product, name: "Sortable Match Pricey", price_cents: 5000)

      get products_path(q: "Sortable Match", sort: "price_desc")

      body = response.body
      expect(body.index(pricey.name)).to be < body.index(cheap.name)
    end

    it "resets to page 1 of the matching results and paginates them" do
      create_list(:product, 14, name: "Paginated Match")

      get products_path(q: "Paginated Match")

      expect(response).to have_http_status(:ok)
      expect(response.body.scan("Paginated Match").size).to be >= 12
    end
  end

  describe "GET /products/:id" do
    it "is visible to guests" do
      product = create(:product)
      get product_path(product)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.name)
    end

    it "marks the favorite button as pressed when the current user favorited it" do
      user = create(:user)
      product = create(:product)
      create(:favorite, user: user, product: product)
      sign_in user

      get product_path(product)

      expect(response.body).to include('aria-pressed="true"')
    end

    it "does not mark the favorite button as pressed for another user's favorite" do
      product = create(:product)
      create(:favorite, user: create(:user), product: product)
      sign_in create(:user)

      get product_path(product)

      expect(response.body).to include('aria-pressed="false"')
    end
  end

  describe "GET /products/by_ids" do
    it "returns json for the requested existing products, ignoring missing ids" do
      keep = create(:product, name: "Keep Me", price_cents: 1200, stock_quantity: 3)

      get by_ids_products_path(ids: [ keep.id, 0 ]), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["id"]).to eq(keep.id)
      expect(body.first["name"]).to eq("Keep Me")
      expect(body.first["price_cents"]).to eq(1200)
      expect(body.first["in_stock"]).to be true
    end

    it "returns an empty array when no ids are given" do
      get by_ids_products_path, as: :json
      expect(JSON.parse(response.body)).to eq([])
    end

    it "includes the fields the comparison feature needs" do
      product = create(:product,
        name: "Nova 12", brand: "Voltrix", model: "Nova 12", category: :smartphones,
        price_cents: 150_000, previous_price_cents: 200_000, warranty_months: 24,
        stock_quantity: 2, specifications: { ram_gb: 8 })

      get by_ids_products_path(ids: [ product.id ]), as: :json

      body = JSON.parse(response.body).first
      expect(body["brand"]).to eq("Voltrix")
      expect(body["model"]).to eq("Nova 12")
      expect(body["category"]).to eq("smartphones")
      expect(body["category_label"]).to eq("Smartphones")
      expect(body["previous_price_cents"]).to eq(200_000)
      expect(body["discounted"]).to eq(true)
      expect(body["stock_quantity"]).to eq(2)
      expect(body["low_stock"]).to eq(true)
      expect(body["out_of_stock"]).to eq(false)
      expect(body["warranty_months"]).to eq(24)
      expect(body["specifications"]).to eq("ram_gb" => 8)
    end
  end

  describe "POST /products" do
    let(:params) do
      {
        product: {
          name: "New Book", description: "desc", price_cents: 1200, stock_quantity: 5,
          sku: "NEW-BOOK-1", brand: "Acme", category: "accessories"
        }
      }
    end

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

    it "lets an admin attach an image on create" do
      sign_in create(:user, :admin)

      post products_path, params: {
        product: {
          name: "New Book", description: "desc", price_cents: 1200, stock_quantity: 5,
          sku: "NEW-BOOK-2", brand: "Acme", category: "accessories",
          image: fixture_file_upload("test_image.png", "image/png")
        }
      }

      expect(Product.last.image).to be_attached
    end

    it "creates the product fine when no image is given" do
      sign_in create(:user, :admin)

      post products_path, params: {
        product: {
          name: "New Book", description: "desc", price_cents: 1200, stock_quantity: 5,
          sku: "NEW-BOOK-3", brand: "Acme", category: "accessories"
        }
      }

      expect(Product.last.image).not_to be_attached
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

    it "lets an admin update the electronics fields, including specifications as a JSON string" do
      product = create(:product)
      sign_in create(:user, :admin)

      patch product_path(product), params: {
        product: {
          brand: "Voltrix", model: "Nova 12", category: "smartphones",
          previous_price_cents: 2000, price_cents: 1500,
          warranty_months: 24, color: "Black", weight_grams: 190,
          specifications: '{"ram_gb": 8, "storage_gb": 128}'
        }
      }

      product.reload
      expect(product.brand).to eq("Voltrix")
      expect(product.category).to eq("smartphones")
      expect(product.previous_price_cents).to eq(2000)
      expect(product.specifications).to eq("ram_gb" => 8, "storage_gb" => 128)
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

    it "is blocked by Rails when the product has already been purchased" do
      product = create(:product)
      order = create(:order)
      create(:order_item, order: order, product: product)
      sign_in create(:user, :admin)

      expect { delete product_path(product) }.not_to change(Product, :count)
      expect(response).to redirect_to(products_path)
      expect(flash[:alert]).to be_present
    end
  end
end
