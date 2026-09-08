# Online Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a server-rendered Rails online store with Devise auth, Pundit authorization, a persistent DB-backed cart, and a fully simulated (non-real) payment/checkout system, on top of the existing fresh `rails new` scaffold.

**Architecture:** Standard Rails MVC. Business-critical checkout logic (locking, stock checks, payment simulation) lives in a plain `CheckoutService` object, not in a controller or callbacks. Pundit policies gate every mutating/scoped action; Devise gates authentication. Views share one layout styled with plain CSS drawing from a Figma book-store template as a loose visual reference.

**Tech Stack:** Rails 8.1.3.1, Ruby 3.3.9, PostgreSQL, Devise, Pundit, RSpec + FactoryBot + Shoulda Matchers, Kaminari (pagination), Faker (test/seed data), database_cleaner-active_record (race-condition spec only).

**Spec:** `docs/superpowers/specs/2026-09-08-online-store-design.md`

## Global Constraints

- Money is stored as integer cents everywhere (`price_cents`, `total_cents`, `balance_cents`) — never floats.
- PostgreSQL only — the scaffold's SQLite/Minitest defaults are removed, not left as an option.
- `role` is a plain enum column on `User` (`user`/`admin`) — no separate roles table.
- `PaymentCard` is global seed data, never associated to a `User`.
- Stock (`Product#stock_quantity`) is checked **only** at checkout, never at add-to-cart.
- Checkout is one DB transaction: lock the cart row, then lock every referenced product row (ordered by id), then proceed. See spec's "Checkout flow & payment simulation" section for the full step order.
- Card numbers are sanitized (strip whitespace/dashes) before lookup; anything left non-numeric or empty is treated as `invalid_card`, never raises.
- Every checkout resolves to `paid` or `failed`; `pending` is never a persisted end state in normal flow.
- No real payment gateway of any kind — this must stay obvious in code comments and the README.
- Server-rendered HTML only — classic Rails forms + redirects, no Turbo Streams/SPA behavior.
- Styling is plain CSS with custom properties under `app/assets/stylesheets` — no CSS framework.
- The Figma book-store reference is orientation, not a pixel-exact target; only Price-range and In-stock filters are implemented on the Products index (Brand/Color/Material don't exist in our schema).

---

## Task 1: Environment setup — PostgreSQL + RSpec/FactoryBot/Shoulda/Faker

**Files:**
- Modify: `Gemfile`
- Modify: `config/database.yml`
- Delete: `test/` (entire directory)
- Create: `spec/spec_helper.rb`, `spec/rails_helper.rb`, `.rspec` (via generator)
- Modify: `spec/rails_helper.rb` (config)

**Interfaces:**
- Produces: a working `bundle exec rspec` command against a real Postgres test database, for every later task to build on.

- [ ] **Step 1: Swap SQLite for PostgreSQL and add the test stack to the Gemfile**

Remove:
```ruby
gem "sqlite3", ">= 2.1"
```

Add near the top (with the other core gems):
```ruby
gem "pg", "~> 1.5"
```

Add a new group after the existing `group :development, :test do ... end` block:
```ruby
group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
end

group :test do
  gem "shoulda-matchers"
end
```

(Leave the existing `capybara`/`selenium-webdriver` `group :test do` block as-is — just add `shoulda-matchers` into it or a second `group :test do` block; either is fine.)

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: resolves cleanly, `Gemfile.lock` updated.

- [ ] **Step 3: Rewrite `config/database.yml` for PostgreSQL**

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000

development:
  <<: *default
  database: shop_trololo_development

test:
  <<: *default
  database: shop_trololo_test
  pool: 6

production:
  <<: *default
  database: shop_trololo_production
  username: shop_trololo
  password: <%= ENV["SHOP_TROLOLO_DATABASE_PASSWORD"] %>
```

The `test` pool is pinned to 6 (not the shared `RAILS_MAX_THREADS` default) so the two concurrent threads in the Task 15 race-condition spec never block waiting on a connection.

Prerequisite: a local PostgreSQL server must be running and reachable with your OS user (no password) for `development`/`test` — e.g. `brew services start postgresql@16` on macOS. If `db:create` below fails with a connection error, start Postgres first.

- [ ] **Step 4: Remove the Minitest scaffold**

Run: `rm -rf test/`

- [ ] **Step 5: Create the databases**

Run: `bin/rails db:create`
Expected: `Created database 'shop_trololo_development'` and `Created database 'shop_trololo_test'`.

- [ ] **Step 6: Install RSpec**

Run: `bin/rails generate rspec:install`
Expected: creates `.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`.

- [ ] **Step 7: Configure `spec/rails_helper.rb`**

Add inside the existing `RSpec.configure do |config| ... end` block (after the `config.use_transactional_fixtures = true` line the generator adds):

```ruby
  config.include FactoryBot::Syntax::Methods
  config.filter_run_excluding :race_condition
```

Add near the top of the file, after `require "rspec/rails"`:

```ruby
require "shoulda/matchers"
```

Add near the bottom of the file, outside the `RSpec.configure` block:

```ruby
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
```

- [ ] **Step 8: Verify the suite boots**

Run: `bundle exec rspec`
Expected: `0 examples, 0 failures` (no test files exist yet — this just proves the Postgres connection, RSpec, FactoryBot, and Shoulda Matchers wiring all work).

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock config/database.yml spec/ .rspec
git commit -m "Switch to PostgreSQL and set up RSpec/FactoryBot/Shoulda Matchers"
```

---

## Task 2: Devise, User role, and the full route map

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/devise.rb`, `db/migrate/*_devise_create_users.rb` (via generator)
- Create: `app/models/user.rb` (via generator, then edited)
- Create: `db/migrate/*_add_role_to_users.rb`
- Modify: `config/routes.rb`
- Create: `spec/factories/users.rb`
- Create: `spec/models/user_spec.rb`

**Interfaces:**
- Produces: `User` model with `enum :role, { user: 0, admin: 1 }`, `role`/`admin?`/`user?` methods (from the enum), Devise's `current_user`/`user_signed_in?`/`authenticate_user!` available in every controller, and every named route path helper used by later tasks (`products_path`, `cart_path`, `cart_items_path`, `new_checkout_path`/`checkout_path`, `orders_path`/`order_path`, `new_user_session_path`, etc.) — even though most of their controllers don't exist yet. Referencing those path helpers from a view is safe before the controller exists; only *dispatching a request* to one requires the controller to exist.

- [ ] **Step 1: Add Devise**

Add to `Gemfile` (near `pg`):
```ruby
gem "devise"
```

Run: `bundle install`

- [ ] **Step 2: Install Devise and generate the User model**

Run: `bin/rails generate devise:install`
Run: `bin/rails generate devise User`
Expected: creates `db/migrate/*_devise_create_users.rb`, `app/models/user.rb`, updates `config/routes.rb` with `devise_for :users`.

- [ ] **Step 3: Add the `role` column**

Run: `bin/rails generate migration AddRoleToUsers role:integer`

Edit the generated migration to add `default: 0, null: false`:
```ruby
class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role, :integer, default: 0, null: false
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Write the failing model spec**

Create `spec/factories/users.rb`:
```ruby
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }

    trait :admin do
      role { :admin }
    end
  end
end
```

Create `spec/models/user_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe User, type: :model do
  it { is_expected.to define_enum_for(:role).with_values(user: 0, admin: 1) }

  it "defaults to the user role" do
    expect(create(:user).role).to eq("user")
  end

  it "is not an admin by default" do
    expect(create(:user)).not_to be_admin
  end

  it "is an admin with the :admin trait" do
    expect(create(:user, :admin)).to be_admin
  end
end
```

- [ ] **Step 2: Run and confirm it fails**

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: FAIL — `role` enum not defined yet (`User` model only has Devise modules so far).

- [ ] **Step 3: Add the enum to `User`**

Edit `app/models/user.rb` — it currently looks like:
```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
end
```

Change to:
```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum :role, { user: 0, admin: 1 }, default: :user
end
```

- [ ] **Step 4: Run and confirm it passes**

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: PASS, 4 examples, 0 failures.

- [ ] **Step 5: Write the complete route map**

Replace the contents of `config/routes.rb` (keep the `devise_for :users` line the generator added):
```ruby
Rails.application.routes.draw do
  devise_for :users

  root "products#index"

  resources :products
  resource :cart, only: [:show]
  resources :cart_items, only: [:create, :update, :destroy]
  resource :checkout, only: [:new, :create]
  resources :orders, only: [:index, :show]

  get "up" => "rails/health#show", as: :rails_health_check
end
```

(Keep whatever health-check / PWA routes the generator already added below `devise_for :users` — merge rather than delete them if present.)

- [ ] **Step 6: Verify routes load**

Run: `bin/rails routes | grep -E "products|cart|checkout|orders"`
Expected: lists all the named routes above, even though most controllers don't exist yet (Rails only resolves a route's controller when a request is dispatched to it, not at boot).

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/devise.rb config/routes.rb \
  db/migrate app/models/user.rb spec/factories/users.rb spec/models/user_spec.rb db/schema.rb
git commit -m "Add Devise auth, User role enum, and the full route map"
```

---

## Task 3: Pundit wiring and ApplicationPolicy

**Files:**
- Modify: `Gemfile`
- Create: `app/policies/application_policy.rb`
- Modify: `app/controllers/application_controller.rb`

**Interfaces:**
- Consumes: `current_user` (Devise, from Task 2).
- Produces: `include Pundit::Authorization` on `ApplicationController` (so every controller gets `authorize`/`policy_scope`), a `Pundit::NotAuthorizedError` → HTTP 403 rescue, and `ApplicationPolicy` as the base class every resource policy inherits from.

- [ ] **Step 1: Add Pundit**

Add to `Gemfile`:
```ruby
gem "pundit"
```

Run: `bundle install`

- [ ] **Step 2: Generate the base policy**

Run: `bin/rails generate pundit:install`
Expected: creates `app/policies/application_policy.rb`. Replace its contents with:

```ruby
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "You must define #resolve in #{self.class}"
    end
  end
end
```

- [ ] **Step 3: Wire `ApplicationController`**

Edit `app/controllers/application_controller.rb`:
```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

  private

  def render_forbidden
    render plain: "Forbidden", status: :forbidden
  end
end
```

- [ ] **Step 4: Verify the app still boots**

Run: `bin/rails runner "puts 'ok'"`
Expected: prints `ok` with no load errors (there's nothing to authorize yet, so this task has no spec of its own — the 403 behavior is exercised for real starting in Task 6's `ProductPolicy` spec and Task 7's request specs).

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock app/policies/application_policy.rb app/controllers/application_controller.rb
git commit -m "Install Pundit and wire 403 handling into ApplicationController"
```

---

## Task 4: Shared layout and base CSS shell

**Files:**
- Create: `app/views/layouts/application.html.erb` (modify existing)
- Create: `app/views/shared/_header.html.erb`
- Create: `app/views/shared/_footer.html.erb`
- Create: `app/views/shared/_flash.html.erb`
- Create: `app/assets/stylesheets/application.css`
- Create: `app/assets/stylesheets/layout.css`
- Create: `app/assets/stylesheets/forms.css`
- Test: `spec/requests/layout_spec.rb`

**Interfaces:**
- Consumes: `user_signed_in?`, `current_user`, Devise path helpers (Task 2); `products_path`, `cart_path`, `orders_path`, `new_product_path` (Task 2 routes).
- Produces: the `application` layout every controller renders into by default, plus reusable `shared/_flash` partial any controller's views can render.

This is verified against Devise's own sign-in page, which already exists after Task 2 — no other resource needs to exist yet.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/layout_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Application layout", type: :request do
  it "renders the shared header and footer around every page" do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Shop Trololo")
    expect(response.body).to include("simulated")
  end
end
```

- [ ] **Step 2: Run and confirm it fails**

Run: `bundle exec rspec spec/requests/layout_spec.rb`
Expected: FAIL — the default layout doesn't contain "Shop Trololo" or "simulated" anywhere yet.

- [ ] **Step 3: Write the header partial**

Create `app/views/shared/_header.html.erb`:
```erb
<header class="site-header">
  <div class="utility-bar">
    <span>This is a simulated store — no real payments are processed.</span>
    <nav class="utility-bar__auth">
      <% if user_signed_in? %>
        <span><%= current_user.email %> (<%= current_user.role %>)</span>
        <%= button_to "Sign out", destroy_user_session_path, method: :delete, class: "link-button" %>
      <% else %>
        <%= link_to "Sign in", new_user_session_path %>
        <%= link_to "Sign up", new_user_registration_path %>
      <% end %>
    </nav>
  </div>
  <div class="main-header">
    <%= link_to "Shop Trololo", root_path, class: "logo" %>
    <nav class="main-nav">
      <%= link_to "Products", products_path %>
      <% if user_signed_in? && current_user.admin? %>
        <%= link_to "New Product", new_product_path %>
      <% end %>
    </nav>
    <div class="header-actions">
      <% if user_signed_in? %>
        <%= link_to "Cart", cart_path, class: "cart-link" %>
        <%= link_to "My Orders", orders_path %>
      <% end %>
    </div>
  </div>
</header>
```

(The cart item-count badge is added to this partial in Task 8, once `Cart` exists.)

- [ ] **Step 4: Write the footer partial**

Create `app/views/shared/_footer.html.erb`:
```erb
<footer class="site-footer">
  <div class="site-footer__brand">
    <p class="site-footer__logo">Shop Trololo</p>
    <p>A simulated online store — no real payments are processed.</p>
  </div>
  <div class="site-footer__links">
    <h4>Shop</h4>
    <%= link_to "Products", products_path %>
  </div>
  <div class="site-footer__links">
    <h4>Account</h4>
    <% if user_signed_in? %>
      <%= link_to "My Orders", orders_path %>
    <% else %>
      <%= link_to "Sign in", new_user_session_path %>
    <% end %>
  </div>
</footer>
```

- [ ] **Step 5: Write the flash partial**

Create `app/views/shared/_flash.html.erb`:
```erb
<% if notice %>
  <div class="flash flash--notice"><%= notice %></div>
<% end %>
<% if alert %>
  <div class="flash flash--alert"><%= alert %></div>
<% end %>
```

- [ ] **Step 6: Write the base CSS**

Create `app/assets/stylesheets/application.css`:
```css
:root {
  --color-navy: #1b2555;
  --color-navy-dark: #12193d;
  --color-coral: #e85c41;
  --color-coral-dark: #d14a30;
  --color-bg: #ffffff;
  --color-bg-soft: #fdeceb;
  --color-text: #23264a;
  --color-text-muted: #6b7280;
  --color-border: #e5e7eb;
  --font-heading: "Poppins", sans-serif;
  --font-body: "Inter", sans-serif;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: var(--font-body);
  color: var(--color-text);
  background: var(--color-bg);
}

h1, h2, h3, h4 {
  font-family: var(--font-heading);
  color: var(--color-navy);
  margin: 0 0 0.5em;
}

a {
  color: var(--color-navy);
}

.page {
  max-width: 1200px;
  margin: 0 auto;
  padding: 2rem 1.5rem;
  min-height: 60vh;
}
```

Create `app/assets/stylesheets/layout.css`:
```css
.site-header .utility-bar {
  background: var(--color-navy);
  color: white;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.5rem 1.5rem;
  font-size: 0.85rem;
}

.site-header .utility-bar a,
.site-header .utility-bar .link-button {
  color: white;
  margin-left: 1rem;
}

.site-header .main-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1rem 1.5rem;
  border-bottom: 1px solid var(--color-border);
}

.site-header .logo {
  font-family: var(--font-heading);
  font-weight: 700;
  font-size: 1.5rem;
  text-decoration: none;
  color: var(--color-navy);
}

.site-header .main-nav a {
  margin-right: 1.5rem;
  text-decoration: none;
  color: var(--color-navy);
  font-weight: 500;
}

.site-header .header-actions a {
  margin-left: 1rem;
  text-decoration: none;
  color: var(--color-coral);
  font-weight: 600;
}

.site-footer {
  background: var(--color-coral);
  color: white;
  display: flex;
  gap: 3rem;
  padding: 2.5rem 1.5rem;
  margin-top: 3rem;
}

.site-footer a {
  color: white;
  display: block;
  margin-bottom: 0.4rem;
}

.site-footer__logo {
  font-family: var(--font-heading);
  font-weight: 700;
  font-size: 1.25rem;
}
```

Create `app/assets/stylesheets/forms.css`:
```css
.btn {
  display: inline-block;
  padding: 0.6rem 1.2rem;
  border-radius: 6px;
  border: none;
  cursor: pointer;
  font-weight: 600;
  text-decoration: none;
  font-family: var(--font-body);
}

.btn--primary { background: var(--color-navy); color: white; }
.btn--accent { background: var(--color-coral); color: white; }
.btn--secondary { background: white; color: var(--color-navy); border: 1px solid var(--color-navy); }
.btn--danger { background: white; color: #b3261e; border: 1px solid #b3261e; }
.btn--small { padding: 0.3rem 0.7rem; font-size: 0.85rem; }
.btn--large { padding: 0.9rem 1.6rem; font-size: 1.05rem; }

.link-button {
  background: none;
  border: none;
  padding: 0;
  font: inherit;
  cursor: pointer;
  text-decoration: underline;
}

.field { margin-bottom: 1rem; }
.field label { display: block; font-weight: 600; margin-bottom: 0.3rem; }

input[type="text"],
input[type="number"],
input[type="email"],
input[type="password"],
textarea,
select {
  width: 100%;
  padding: 0.5rem;
  border: 1px solid var(--color-border);
  border-radius: 4px;
  font-family: var(--font-body);
}

.form-errors {
  background: #fdecea;
  color: #b3261e;
  padding: 0.8rem 1rem;
  border-radius: 6px;
  margin-bottom: 1rem;
}

.flash { padding: 0.8rem 1rem; border-radius: 6px; margin-bottom: 1rem; }
.flash--notice { background: #e6f4ea; color: #1e7b34; }
.flash--alert { background: #fdecea; color: #b3261e; }

.status-badge { padding: 0.2rem 0.6rem; border-radius: 999px; font-size: 0.8rem; font-weight: 600; }
.status-badge--pending { background: #fff3cd; color: #8a6d00; }
.status-badge--paid { background: #e6f4ea; color: #1e7b34; }
.status-badge--failed { background: #fdecea; color: #b3261e; }
```

- [ ] **Step 7: Wire the layout**

Edit `app/views/layouts/application.html.erb`:
```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Shop Trololo</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@600;700&family=Inter:wght@400;500&display=swap" rel="stylesheet">

    <%= stylesheet_link_tag "application", "layout", "forms", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body>
    <%= render "shared/header" %>
    <main class="page">
      <%= render "shared/flash" %>
      <%= yield %>
    </main>
    <%= render "shared/footer" %>
  </body>
</html>
```

- [ ] **Step 8: Run and confirm it passes**

Run: `bundle exec rspec spec/requests/layout_spec.rb`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add app/views/layouts/application.html.erb app/views/shared \
  app/assets/stylesheets/application.css app/assets/stylesheets/layout.css app/assets/stylesheets/forms.css \
  spec/requests/layout_spec.rb
git commit -m "Add shared header/footer layout and base CSS system"
```

---

## Task 5: Product model

**Files:**
- Create: `db/migrate/*_create_products.rb`
- Create: `app/models/product.rb`
- Create: `spec/factories/products.rb`
- Create: `spec/models/product_spec.rb`
- Create: `spec/fixtures/files/test_image.png`

**Interfaces:**
- Produces: `Product` with `name`, `description`, `price_cents`, `stock_quantity`, `has_one_attached :image`; scopes `Product.in_stock`, `Product.price_gteq(cents)`, `Product.price_lteq(cents)`, `Product.sorted(key)` where `key` is one of `"name_asc"`, `"name_desc"`, `"price_asc"`, `"price_desc"`.

- [ ] **Step 1: Install Active Storage**

Run: `bin/rails active_storage:install`
Run: `bin/rails db:migrate`
Expected: creates `active_storage_blobs`/`active_storage_attachments`/`active_storage_variant_records` tables.

- [ ] **Step 2: Generate the Product migration**

Run: `bin/rails generate model Product name:string description:text price_cents:integer stock_quantity:integer`

Edit the generated migration to add `null: false` and a default:
```ruby
class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.text :description
      t.integer :price_cents, null: false
      t.integer :stock_quantity, null: false, default: 0

      t.timestamps
    end
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 3: Add a tiny fixture image for attachment specs**

Run:
```bash
mkdir -p spec/fixtures/files
python3 -c "
import base64
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
open('spec/fixtures/files/test_image.png', 'wb').write(png)
"
```
Expected: creates a valid 1x1 PNG at `spec/fixtures/files/test_image.png`.

- [ ] **Step 4: Write the factory**

Create `spec/factories/products.rb`:
```ruby
FactoryBot.define do
  factory :product do
    sequence(:name) { |n| "Product #{n}" }
    description { "A great product." }
    price_cents { 1000 }
    stock_quantity { 10 }
  end
end
```

- [ ] **Step 5: Write the failing model spec**

Create `spec/models/product_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Product, type: :model do
  it { is_expected.to have_many(:cart_items).dependent(:destroy) }
  it { is_expected.to have_many(:order_items).dependent(:restrict_with_error) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_numericality_of(:price_cents).is_greater_than(0) }
  it { is_expected.to validate_numericality_of(:stock_quantity).is_greater_than_or_equal_to(0) }

  describe ".in_stock" do
    it "excludes products with zero stock" do
      in_stock = create(:product, stock_quantity: 1)
      out_of_stock = create(:product, stock_quantity: 0)

      expect(Product.in_stock).to include(in_stock)
      expect(Product.in_stock).not_to include(out_of_stock)
    end
  end

  describe ".price_gteq / .price_lteq" do
    it "filters by a price range" do
      cheap = create(:product, price_cents: 500)
      pricey = create(:product, price_cents: 5000)

      result = Product.price_gteq(1000).price_lteq(6000)
      expect(result).to include(pricey)
      expect(result).not_to include(cheap)
    end
  end

  describe ".sorted" do
    it "sorts by price descending" do
      cheap = create(:product, price_cents: 500)
      pricey = create(:product, price_cents: 5000)

      expect(Product.sorted("price_desc").to_a).to eq([pricey, cheap])
    end

    it "falls back to name ascending for an unknown key" do
      b = create(:product, name: "B Product")
      a = create(:product, name: "A Product")

      expect(Product.sorted("nonsense").to_a).to eq([a, b])
    end
  end

  describe "image attachment" do
    it "can have an image attached, and works fine without one" do
      product = create(:product)
      expect(product.image).not_to be_attached

      product.image.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/test_image.png")),
        filename: "test_image.png",
        content_type: "image/png"
      )
      expect(product.image).to be_attached
    end
  end
end
```

- [ ] **Step 6: Run and confirm it fails**

Run: `bundle exec rspec spec/models/product_spec.rb`
Expected: FAIL — `Product` model has no validations/scopes/attachment yet.

- [ ] **Step 7: Implement `Product`**

Create `app/models/product.rb`:
```ruby
class Product < ApplicationRecord
  has_many :cart_items, dependent: :destroy
  has_many :order_items, dependent: :restrict_with_error
  has_one_attached :image

  validates :name, presence: true
  validates :price_cents, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :stock_quantity, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  scope :in_stock, -> { where("stock_quantity > 0") }
  scope :price_gteq, ->(cents) { cents.present? ? where("price_cents >= ?", cents) : all }
  scope :price_lteq, ->(cents) { cents.present? ? where("price_cents <= ?", cents) : all }

  SORT_OPTIONS = {
    "name_asc" => { name: :asc },
    "name_desc" => { name: :desc },
    "price_asc" => { price_cents: :asc },
    "price_desc" => { price_cents: :desc }
  }.freeze

  def self.sorted(key)
    order(SORT_OPTIONS.fetch(key, SORT_OPTIONS["name_asc"]))
  end
end
```

- [ ] **Step 8: Run and confirm it passes**

Run: `bundle exec rspec spec/models/product_spec.rb`
Expected: PASS, all examples green.

- [ ] **Step 9: Commit**

```bash
git add db/migrate db/schema.rb app/models/product.rb spec/factories/products.rb \
  spec/models/product_spec.rb spec/fixtures/files/test_image.png
git commit -m "Add Product model with price/stock scopes and image attachment"
```

---

## Task 6: ProductPolicy

**Files:**
- Create: `app/policies/product_policy.rb`
- Create: `spec/policies/product_policy_spec.rb`

**Interfaces:**
- Consumes: `ApplicationPolicy` (Task 3), `Product` (Task 5), `User#admin?` (Task 2).
- Produces: `ProductPolicy.new(user, product).{index?,show?,create?,update?,destroy?}`, used by `ProductsController` in Task 7.

- [ ] **Step 1: Write the failing policy spec**

Create `spec/policies/product_policy_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe ProductPolicy do
  let(:guest) { nil }
  let(:user) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:product) { Product.new }

  describe "#index? and #show?" do
    it "is true for everyone, including guests" do
      expect(described_class.new(guest, product).index?).to be true
      expect(described_class.new(user, product).index?).to be true
      expect(described_class.new(admin, product).index?).to be true

      expect(described_class.new(guest, product).show?).to be true
      expect(described_class.new(user, product).show?).to be true
    end
  end

  describe "#create?, #update?, #destroy?" do
    it "denies guests and regular users" do
      expect(described_class.new(guest, product).create?).to be false
      expect(described_class.new(user, product).create?).to be false
      expect(described_class.new(user, product).update?).to be false
      expect(described_class.new(user, product).destroy?).to be false
    end

    it "grants admins" do
      expect(described_class.new(admin, product).create?).to be true
      expect(described_class.new(admin, product).update?).to be true
      expect(described_class.new(admin, product).destroy?).to be true
    end
  end
end
```

- [ ] **Step 2: Run and confirm it fails**

Run: `bundle exec rspec spec/policies/product_policy_spec.rb`
Expected: FAIL — `uninitialized constant ProductPolicy`.

- [ ] **Step 3: Implement `ProductPolicy`**

Create `app/policies/product_policy.rb`:
```ruby
class ProductPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    user&.admin? || false
  end

  def update?
    user&.admin? || false
  end

  def destroy?
    user&.admin? || false
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
```

- [ ] **Step 4: Run and confirm it passes**

Run: `bundle exec rspec spec/policies/product_policy_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/policies/product_policy.rb spec/policies/product_policy_spec.rb
git commit -m "Add ProductPolicy: public read, admin-only write"
```

---

## Task 7: ProductsController, views, and CSS

**Files:**
- Modify: `Gemfile`
- Create: `app/controllers/products_controller.rb`
- Create: `app/views/products/index.html.erb`, `show.html.erb`, `_form.html.erb`, `new.html.erb`, `edit.html.erb`
- Create: `app/assets/stylesheets/products.css`
- Create: `spec/requests/products_spec.rb`

**Interfaces:**
- Consumes: `Product` (Task 5), `ProductPolicy` (Task 6), `authorize`/Pundit 403 handling (Task 3), shared layout (Task 4).
- Produces: `GET/POST/PATCH/DELETE /products[...]`, rendering into the shared layout.

- [ ] **Step 1: Add Kaminari for pagination**

Add to `Gemfile`:
```ruby
gem "kaminari"
```
Run: `bundle install`

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/products_spec.rb`:
```ruby
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
```

- [ ] **Step 3: Run and confirm it fails**

Run: `bundle exec rspec spec/requests/products_spec.rb`
Expected: FAIL — no `ProductsController`/routes to a real controller yet (`AbstractController::ActionNotFound` or similar).

- [ ] **Step 4: Implement `ProductsController`**

Create `app/controllers/products_controller.rb`:
```ruby
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
```

- [ ] **Step 5: Implement the views**

Create `app/views/products/index.html.erb`:
```erb
<h1>Products</h1>

<div class="products-layout">
  <aside class="filters">
    <%= form_with url: products_path, method: :get, class: "filters__form" do %>
      <fieldset>
        <legend>Price</legend>
        <label>Min <%= number_field_tag :min_price, params[:min_price], step: "0.01", min: 0 %></label>
        <label>Max <%= number_field_tag :max_price, params[:max_price], step: "0.01", min: 0 %></label>
      </fieldset>
      <fieldset>
        <legend>Availability</legend>
        <label>
          <%= check_box_tag :in_stock, "1", params[:in_stock] == "1" %>
          In stock only
        </label>
      </fieldset>
      <div class="field">
        <label for="sort">Sort by</label>
        <%= select_tag :sort, options_for_select(
              [["Name (A-Z)", "name_asc"], ["Name (Z-A)", "name_desc"],
               ["Price (low to high)", "price_asc"], ["Price (high to low)", "price_desc"]],
              params[:sort]) %>
      </div>
      <%= submit_tag "Filter", class: "btn btn--primary" %>
    <% end %>
  </aside>

  <section>
    <div class="product-grid">
      <% @products.each do |product| %>
        <article class="product-card">
          <%= link_to product_path(product) do %>
            <% if product.image.attached? %>
              <%= image_tag product.image, class: "product-card__image" %>
            <% else %>
              <div class="product-card__image product-card__image--placeholder"></div>
            <% end %>
          <% end %>
          <h3><%= link_to product.name, product_path(product) %></h3>
          <p class="product-card__price">$<%= "%.2f" % (product.price_cents / 100.0) %></p>
          <% if product.stock_quantity <= 0 %>
            <p class="product-card__out-of-stock">Out of stock</p>
          <% elsif user_signed_in? %>
            <%= button_to "Add to Cart", cart_items_path(product_id: product.id), class: "btn btn--accent" %>
          <% end %>
        </article>
      <% end %>
    </div>

    <%= paginate @products %>
  </section>
</div>
```

Create `app/views/products/show.html.erb`:
```erb
<div class="product-detail">
  <% if @product.image.attached? %>
    <%= image_tag @product.image, class: "product-detail__image" %>
  <% end %>

  <div class="product-detail__info">
    <h1><%= @product.name %></h1>
    <p class="product-detail__price">$<%= "%.2f" % (@product.price_cents / 100.0) %></p>
    <p><%= @product.description %></p>
    <p><%= @product.stock_quantity > 0 ? "#{@product.stock_quantity} in stock" : "Out of stock" %></p>

    <% if user_signed_in? %>
      <%= form_with url: cart_items_path, method: :post, class: "add-to-cart-form" do %>
        <%= hidden_field_tag :product_id, @product.id %>
        <%= number_field_tag :quantity, 1, min: 1, class: "quantity-input" %>
        <%= submit_tag "Add to Cart", class: "btn btn--accent" %>
      <% end %>
    <% else %>
      <%= link_to "Sign in to purchase", new_user_session_path, class: "btn btn--primary" %>
    <% end %>

    <% if user_signed_in? && current_user.admin? %>
      <div class="admin-actions">
        <%= link_to "Edit", edit_product_path(@product), class: "btn btn--secondary" %>
        <%= button_to "Delete", product_path(@product), method: :delete, class: "btn btn--danger",
              form: { data: { turbo_confirm: "Delete this product?" } } %>
      </div>
    <% end %>
  </div>
</div>
```

Create `app/views/products/_form.html.erb`:
```erb
<%= form_with model: product, class: "product-form" do |f| %>
  <% if product.errors.any? %>
    <div class="form-errors">
      <ul>
        <% product.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="field">
    <%= f.label :name %>
    <%= f.text_field :name %>
  </div>
  <div class="field">
    <%= f.label :description %>
    <%= f.text_area :description %>
  </div>
  <div class="field">
    <%= f.label :price_cents, "Price (cents)" %>
    <%= f.number_field :price_cents, min: 1, step: 1 %>
  </div>
  <div class="field">
    <%= f.label :stock_quantity %>
    <%= f.number_field :stock_quantity, min: 0, step: 1 %>
  </div>
  <div class="field">
    <%= f.label :image %>
    <%= f.file_field :image, accept: "image/*" %>
    <% if product.image.attached? %>
      <%= image_tag product.image, class: "product-form__current-image" %>
    <% end %>
  </div>

  <%= f.submit class: "btn btn--primary" %>
<% end %>
```

Create `app/views/products/new.html.erb`:
```erb
<h1>New Product</h1>
<%= render "form", product: @product %>
```

Create `app/views/products/edit.html.erb`:
```erb
<h1>Edit Product</h1>
<%= render "form", product: @product %>
```

- [ ] **Step 6: Write the products CSS**

Create `app/assets/stylesheets/products.css`:
```css
.products-layout {
  display: grid;
  grid-template-columns: 220px 1fr;
  gap: 2rem;
}

.filters {
  border: 1px solid var(--color-border);
  border-radius: 8px;
  padding: 1rem;
  align-self: start;
}

.filters fieldset { border: none; padding: 0; margin: 0 0 1rem; }
.filters legend { font-weight: 600; color: var(--color-navy); margin-bottom: 0.5rem; }
.filters label { display: block; margin-bottom: 0.4rem; }

.product-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 1.5rem;
}

.product-card {
  border: 1px solid var(--color-border);
  border-radius: 8px;
  padding: 1rem;
  text-align: center;
}

.product-card__image { width: 100%; height: 220px; object-fit: cover; border-radius: 4px; }
.product-card__image--placeholder { background: var(--color-bg-soft); }
.product-card__price { color: var(--color-coral); font-weight: 700; }
.product-card__out-of-stock { color: var(--color-text-muted); font-style: italic; }

.product-detail { display: grid; grid-template-columns: 1fr 1fr; gap: 2rem; }
.product-detail__image { width: 100%; border-radius: 8px; }
.product-detail__price { font-size: 1.5rem; color: var(--color-coral); font-weight: 700; }

.pagination {
  display: flex;
  gap: 0.5rem;
  justify-content: center;
  margin-top: 2rem;
  list-style: none;
  padding: 0;
}
.pagination a, .pagination span {
  padding: 0.4rem 0.8rem;
  border: 1px solid var(--color-border);
  border-radius: 999px;
  text-decoration: none;
  color: var(--color-navy);
}
.pagination .current { background: var(--color-coral); color: white; border-color: var(--color-coral); }
```

Add the stylesheet link in `app/views/layouts/application.html.erb` (edit the existing `stylesheet_link_tag` line from Task 4):
```erb
<%= stylesheet_link_tag "application", "layout", "forms", "products", "data-turbo-track": "reload" %>
```

- [ ] **Step 7: Run and confirm it passes**

Run: `bundle exec rspec spec/requests/products_spec.rb`
Expected: PASS, all examples green.

- [ ] **Step 8: Commit**

```bash
git add Gemfile Gemfile.lock app/controllers/products_controller.rb app/views/products \
  app/assets/stylesheets/products.css app/views/layouts/application.html.erb spec/requests/products_spec.rb
git commit -m "Add ProductsController with filters/sort/pagination and views"
```

---

## Task 8: Cart and CartItem models

**Files:**
- Create: `db/migrate/*_create_carts.rb`, `db/migrate/*_create_cart_items.rb`
- Create: `app/models/cart.rb`, `app/models/cart_item.rb`
- Modify: `app/models/user.rb`
- Modify: `app/views/shared/_header.html.erb`
- Create: `spec/factories/cart_items.rb`
- Create: `spec/models/cart_spec.rb`, `spec/models/cart_item_spec.rb`, update `spec/models/user_spec.rb`

**Interfaces:**
- Consumes: `User` (Task 2), `Product` (Task 5).
- Produces: `User#cart` (auto-created on user creation), `Cart#total_cents`, `Cart#cart_items`, `CartItem` with `quantity` validation and a `[cart_id, product_id]` uniqueness constraint.

**Gotcha for the implementer:** do **not** add a `factory :cart` that builds its own `user`. `User` auto-creates its cart on creation (`after_create :create_default_cart` below), so a cart factory that also builds a user would create two carts for one user and violate the unique index on `carts.user_id`. Everywhere a cart is needed in specs, use `create(:user).cart` — see `spec/factories/cart_items.rb` below for the pattern.

- [ ] **Step 1: Generate the migrations**

Run: `bin/rails generate model Cart user:references`

Edit the generated migration to make the `user_id` reference unique:
```ruby
class CreateCarts < ActiveRecord::Migration[8.1]
  def change
    create_table :carts do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.timestamps
    end
  end
end
```

Run: `bin/rails generate model CartItem cart:references product:references quantity:integer`

Edit the generated migration:
```ruby
class CreateCartItems < ActiveRecord::Migration[8.1]
  def change
    create_table :cart_items do |t|
      t.references :cart, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1

      t.timestamps
    end

    add_index :cart_items, [:cart_id, :product_id], unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Write the failing specs**

Add to `spec/models/user_spec.rb` (inside the existing `RSpec.describe User do` block):
```ruby
  it { is_expected.to have_one(:cart).dependent(:destroy) }
  it { is_expected.to have_many(:orders) }

  it "creates a cart automatically when the user is created" do
    expect(create(:user).cart).to be_present
  end
```

Create `spec/factories/cart_items.rb`:
```ruby
FactoryBot.define do
  factory :cart_item do
    cart { association(:user).cart }
    product
    quantity { 1 }
  end
end
```

Create `spec/models/cart_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Cart, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:cart_items).dependent(:destroy) }

  describe "#total_cents" do
    it "sums price times quantity across all items" do
      cart = create(:user).cart
      product_a = create(:product, price_cents: 1000)
      product_b = create(:product, price_cents: 500)
      cart.cart_items.create!(product: product_a, quantity: 2)
      cart.cart_items.create!(product: product_b, quantity: 3)

      expect(cart.total_cents).to eq((1000 * 2) + (500 * 3))
    end

    it "is zero for an empty cart" do
      cart = create(:user).cart
      expect(cart.total_cents).to eq(0)
    end
  end
end
```

Create `spec/models/cart_item_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe CartItem, type: :model do
  it { is_expected.to belong_to(:cart) }
  it { is_expected.to belong_to(:product) }
  it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(1).only_integer }

  it "does not allow the same product twice in one cart" do
    cart = create(:user).cart
    product = create(:product)
    create(:cart_item, cart: cart, product: product)

    duplicate = build(:cart_item, cart: cart, product: product)

    expect(duplicate).not_to be_valid
  end

  it "does not validate against product stock" do
    product = create(:product, stock_quantity: 0)
    cart_item = build(:cart_item, product: product, quantity: 99)

    expect(cart_item).to be_valid
  end
end
```

- [ ] **Step 3: Run and confirm it fails**

Run: `bundle exec rspec spec/models/cart_spec.rb spec/models/cart_item_spec.rb spec/models/user_spec.rb`
Expected: FAIL — `Cart`/`CartItem` don't exist as intended yet, `User#cart` isn't wired.

- [ ] **Step 4: Implement `Cart`**

Create `app/models/cart.rb`:
```ruby
class Cart < ApplicationRecord
  belongs_to :user
  has_many :cart_items, dependent: :destroy
  has_many :products, through: :cart_items

  def total_cents
    cart_items.joins(:product).sum("products.price_cents * cart_items.quantity")
  end
end
```

- [ ] **Step 5: Implement `CartItem`**

Create `app/models/cart_item.rb`:
```ruby
class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :product

  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :product_id, uniqueness: { scope: :cart_id }

  # Stock availability is intentionally NOT checked here. CheckoutService
  # is the single source of truth for stock availability — see the
  # "Stock is checked at checkout, not at add-to-cart" section of
  # docs/superpowers/specs/2026-09-08-online-store-design.md. A cart may
  # legitimately hold more of a product than is currently in stock; that
  # surfaces as an out-of-stock failure at checkout, not here. Do not
  # "fix" this by adding a stock check to this model or its controller.
end
```

- [ ] **Step 6: Wire `User#cart` and auto-creation**

Edit `app/models/user.rb`:
```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum :role, { user: 0, admin: 1 }, default: :user

  has_one :cart, dependent: :destroy
  has_many :orders, dependent: :destroy

  after_create :create_default_cart

  private

  def create_default_cart
    create_cart!
  end
end
```

- [ ] **Step 7: Run and confirm it passes**

Run: `bundle exec rspec spec/models/cart_spec.rb spec/models/cart_item_spec.rb spec/models/user_spec.rb`
Expected: PASS, all examples green.

- [ ] **Step 8: Add the cart-count badge to the header**

Edit `app/views/shared/_header.html.erb` — change:
```erb
        <%= link_to "Cart", cart_path, class: "cart-link" %>
```
to:
```erb
        <%= link_to "Cart (#{current_user.cart.cart_items.sum(:quantity)})", cart_path, class: "cart-link" %>
```

- [ ] **Step 9: Confirm the full suite still passes**

Run: `bundle exec rspec`
Expected: all examples still green (the header change touches every signed-in page).

- [ ] **Step 10: Commit**

```bash
git add db/migrate db/schema.rb app/models/cart.rb app/models/cart_item.rb app/models/user.rb \
  app/views/shared/_header.html.erb spec/factories/cart_items.rb spec/models/cart_spec.rb \
  spec/models/cart_item_spec.rb spec/models/user_spec.rb
git commit -m "Add Cart/CartItem models with auto-created per-user cart"
```

---

## Task 9: CartItemPolicy

**Files:**
- Create: `app/policies/cart_item_policy.rb`
- Create: `spec/policies/cart_item_policy_spec.rb`

**Interfaces:**
- Consumes: `ApplicationPolicy` (Task 3), `CartItem` (Task 8).
- Produces: `CartItemPolicy.new(user, cart_item).{create?,update?,destroy?}`, used by `CartItemsController` in Task 10.

- [ ] **Step 1: Write the failing policy spec**

Create `spec/policies/cart_item_policy_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe CartItemPolicy do
  describe "#create?, #update?, #destroy?" do
    it "is true only for the cart's own owner" do
      owner = create(:user)
      other = create(:user)
      item = create(:cart_item, cart: owner.cart)

      expect(described_class.new(owner, item).create?).to be true
      expect(described_class.new(owner, item).update?).to be true
      expect(described_class.new(owner, item).destroy?).to be true

      expect(described_class.new(other, item).update?).to be false
      expect(described_class.new(nil, item).update?).to be false
    end
  end
end
```

- [ ] **Step 2: Run and confirm it fails**

Run: `bundle exec rspec spec/policies/cart_item_policy_spec.rb`
Expected: FAIL — `uninitialized constant CartItemPolicy`.

- [ ] **Step 3: Implement `CartItemPolicy`**

Create `app/policies/cart_item_policy.rb`:
```ruby
class CartItemPolicy < ApplicationPolicy
  def create?
    owner?
  end

  def update?
    owner?
  end

  def destroy?
    owner?
  end

  private

  def owner?
    user.present? && record.cart.user_id == user.id
  end
end
```

- [ ] **Step 4: Run and confirm it passes**

Run: `bundle exec rspec spec/policies/cart_item_policy_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/policies/cart_item_policy.rb spec/policies/cart_item_policy_spec.rb
git commit -m "Add CartItemPolicy: owner-only cart mutation"
```

---

## Task 10: CartsController, CartItemsController, and cart views

**Files:**
- Create: `app/controllers/carts_controller.rb`
- Create: `app/controllers/cart_items_controller.rb`
- Create: `app/views/carts/show.html.erb`
- Modify: `app/assets/stylesheets/forms.css` (cart table styles)
- Create: `spec/requests/carts_spec.rb`, `spec/requests/cart_items_spec.rb`

**Interfaces:**
- Consumes: `Cart`/`CartItem` (Task 8), `CartItemPolicy` (Task 9), Pundit 403 (Task 3).
- Produces: `GET /cart`, `POST/PATCH/DELETE /cart_items[...]`.

- [ ] **Step 1: Write the failing request specs**

Create `spec/requests/carts_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Cart", type: :request do
  describe "GET /cart" do
    it "requires sign in" do
      get cart_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "shows the current user's running total" do
      user = create(:user)
      product = create(:product, price_cents: 1000)
      user.cart.cart_items.create!(product: product, quantity: 2)
      sign_in user

      get cart_path

      expect(response.body).to include("20.00")
    end
  end
end
```

Create `spec/requests/cart_items_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Cart items", type: :request do
  describe "POST /cart_items" do
    it "requires sign in" do
      product = create(:product)
      post cart_items_path, params: { product_id: product.id }
      expect(response).to redirect_to(new_user_session_path)
    end

    it "adds a product to the current user's cart" do
      user = create(:user)
      product = create(:product)
      sign_in user

      expect {
        post cart_items_path, params: { product_id: product.id, quantity: 2 }
      }.to change { user.cart.cart_items.count }.by(1)

      expect(user.cart.cart_items.first.quantity).to eq(2)
    end

    it "allows adding more of a product than is currently in stock" do
      user = create(:user)
      product = create(:product, stock_quantity: 1)
      sign_in user

      post cart_items_path, params: { product_id: product.id, quantity: 99 }

      expect(user.cart.cart_items.first.quantity).to eq(99)
    end

    it "increments quantity when the same product is added again" do
      user = create(:user)
      product = create(:product)
      sign_in user
      user.cart.cart_items.create!(product: product, quantity: 1)

      post cart_items_path, params: { product_id: product.id, quantity: 2 }

      expect(user.cart.cart_items.sole.quantity).to eq(3)
    end
  end

  describe "PATCH /cart_items/:id" do
    it "is forbidden when updating another user's cart item" do
      owner = create(:user)
      item = owner.cart.cart_items.create!(product: create(:product), quantity: 1)
      sign_in create(:user)

      patch cart_item_path(item), params: { quantity: 5 }

      expect(response).to have_http_status(:forbidden)
    end

    it "lets the owner update the quantity" do
      user = create(:user)
      item = user.cart.cart_items.create!(product: create(:product), quantity: 1)
      sign_in user

      patch cart_item_path(item), params: { quantity: 5 }

      expect(item.reload.quantity).to eq(5)
    end
  end

  describe "DELETE /cart_items/:id" do
    it "removes the item from the owner's cart" do
      user = create(:user)
      item = user.cart.cart_items.create!(product: create(:product), quantity: 1)
      sign_in user

      expect { delete cart_item_path(item) }.to change { user.cart.cart_items.count }.by(-1)
    end

    it "is forbidden for another user" do
      owner = create(:user)
      item = owner.cart.cart_items.create!(product: create(:product), quantity: 1)
      sign_in create(:user)

      delete cart_item_path(item)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

- [ ] **Step 2: Run and confirm it fails**

Run: `bundle exec rspec spec/requests/carts_spec.rb spec/requests/cart_items_spec.rb`
Expected: FAIL — no `CartsController`/`CartItemsController` yet.

- [ ] **Step 3: Implement `CartsController`**

Create `app/controllers/carts_controller.rb`:
```ruby
class CartsController < ApplicationController
  before_action :authenticate_user!

  def show
    @cart = current_user.cart
  end
end
```

- [ ] **Step 4: Implement `CartItemsController`**

Create `app/controllers/cart_items_controller.rb`:
```ruby
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
```

- [ ] **Step 5: Implement the cart view**

Create `app/views/carts/show.html.erb`:
```erb
<h1>Your Cart</h1>

<% if @cart.cart_items.empty? %>
  <p>Your cart is empty. <%= link_to "Browse products", products_path %>.</p>
<% else %>
  <table class="cart-table">
    <thead>
      <tr><th>Product</th><th>Price</th><th>Quantity</th><th>Subtotal</th><th></th></tr>
    </thead>
    <tbody>
      <% @cart.cart_items.includes(:product).each do |item| %>
        <tr>
          <td><%= item.product.name %></td>
          <td>$<%= "%.2f" % (item.product.price_cents / 100.0) %></td>
          <td>
            <%= form_with url: cart_item_path(item), method: :patch, class: "quantity-form" do %>
              <%= number_field_tag :quantity, item.quantity, min: 1, class: "quantity-input" %>
              <%= submit_tag "Update", class: "btn btn--secondary btn--small" %>
            <% end %>
          </td>
          <td>$<%= "%.2f" % (item.product.price_cents * item.quantity / 100.0) %></td>
          <td><%= button_to "Remove", cart_item_path(item), method: :delete, class: "btn btn--danger btn--small" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>

  <p class="cart-total">Total: $<%= "%.2f" % (@cart.total_cents / 100.0) %></p>
  <%= link_to "Checkout", new_checkout_path, class: "btn btn--accent btn--large" %>
<% end %>
```

- [ ] **Step 6: Add cart table CSS**

Append to `app/assets/stylesheets/forms.css`:
```css
.cart-table, .orders-table, .order-items-table {
  width: 100%;
  border-collapse: collapse;
  margin-bottom: 1.5rem;
}

.cart-table th, .cart-table td,
.orders-table th, .orders-table td,
.order-items-table th, .order-items-table td {
  padding: 0.6rem;
  border-bottom: 1px solid var(--color-border);
  text-align: left;
}

.cart-total {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--color-navy);
}

.quantity-input { width: 4rem; display: inline-block; }
```

- [ ] **Step 7: Run and confirm it passes**

Run: `bundle exec rspec spec/requests/carts_spec.rb spec/requests/cart_items_spec.rb`
Expected: PASS, all examples green.

- [ ] **Step 8: Confirm the full suite still passes**

Run: `bundle exec rspec`

- [ ] **Step 9: Commit**

```bash
git add app/controllers/carts_controller.rb app/controllers/cart_items_controller.rb \
  app/views/carts app/assets/stylesheets/forms.css spec/requests/carts_spec.rb spec/requests/cart_items_spec.rb
git commit -m "Add cart show page and cart item add/update/remove endpoints"
```

---

## Task 11: PaymentCard model

**Files:**
- Create: `db/migrate/*_create_payment_cards.rb`
- Create: `app/models/payment_card.rb`
- Create: `spec/factories/payment_cards.rb`
- Create: `spec/models/payment_card_spec.rb`

**Interfaces:**
- Produces: `PaymentCard` with `card_number` (unique), `holder_name`, `balance_cents`. Global seed data — never associated to a `User`.

- [ ] **Step 1: Generate the migration**

Run: `bin/rails generate model PaymentCard card_number:string holder_name:string balance_cents:integer`

Edit the migration:
```ruby
class CreatePaymentCards < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_cards do |t|
      t.string :card_number, null: false
      t.string :holder_name
      t.integer :balance_cents, null: false, default: 0

      t.timestamps
    end

    add_index :payment_cards, :card_number, unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Write the factory and failing spec**

Create `spec/factories/payment_cards.rb`:
```ruby
FactoryBot.define do
  factory :payment_card do
    sequence(:card_number) { |n| format("42424242%08d", n) }
    holder_name { "Test Cardholder" }
    balance_cents { 10_000 }
  end
end
```

Create `spec/models/payment_card_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe PaymentCard, type: :model do
  it { is_expected.to validate_presence_of(:card_number) }
  it { is_expected.to validate_uniqueness_of(:card_number) }
  it { is_expected.to validate_numericality_of(:balance_cents).is_greater_than_or_equal_to(0) }
end
```

- [ ] **Step 3: Run and confirm it fails**

Run: `bundle exec rspec spec/models/payment_card_spec.rb`
Expected: FAIL — no validations on `PaymentCard` yet.

- [ ] **Step 4: Implement `PaymentCard`**

Create `app/models/payment_card.rb`:
```ruby
# Fake wallet for the simulated payment system. These are NOT real
# payment cards — no real bank or card network is ever contacted.
# See docs/superpowers/specs/2026-09-08-online-store-design.md.
class PaymentCard < ApplicationRecord
  validates :card_number, presence: true, uniqueness: true
  validates :balance_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
```

- [ ] **Step 5: Run and confirm it passes**

Run: `bundle exec rspec spec/models/payment_card_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/payment_card.rb spec/factories/payment_cards.rb spec/models/payment_card_spec.rb
git commit -m "Add PaymentCard model (simulated payment wallet, global seed data)"
```

---

## Task 12: Order and OrderItem models

**Files:**
- Create: `db/migrate/*_create_orders.rb`, `db/migrate/*_create_order_items.rb`
- Create: `app/models/order.rb`, `app/models/order_item.rb`
- Create: `spec/factories/orders.rb`, `spec/factories/order_items.rb`
- Create: `spec/models/order_spec.rb`, `spec/models/order_item_spec.rb`

**Interfaces:**
- Consumes: `User` (Task 2), `Product` (Task 5).
- Produces: `Order` with `enum :status, { pending: 0, paid: 1, failed: 2 }`, `total_cents`, `card_last4`, `failure_reason`; `OrderItem` snapshot fields `product_name`/`unit_price_cents`/`quantity`.

- [ ] **Step 1: Generate the migrations**

Run: `bin/rails generate model Order user:references status:integer total_cents:integer card_last4:string failure_reason:string`

Edit the migration:
```ruby
class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :card_last4
      t.string :failure_reason

      t.timestamps
    end
  end
end
```

Run: `bin/rails generate model OrderItem order:references product:references product_name:string unit_price_cents:integer quantity:integer`

Edit the migration:
```ruby
class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :product_name, null: false
      t.integer :unit_price_cents, null: false
      t.integer :quantity, null: false

      t.timestamps
    end
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 2: Write the factories and failing specs**

Create `spec/factories/orders.rb`:
```ruby
FactoryBot.define do
  factory :order do
    user
    status { :pending }
    total_cents { 0 }
  end
end
```

Create `spec/factories/order_items.rb`:
```ruby
FactoryBot.define do
  factory :order_item do
    order
    product
    product_name { product.name }
    unit_price_cents { product.price_cents }
    quantity { 1 }
  end
end
```

Create `spec/models/order_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Order, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:order_items).dependent(:destroy) }
  it { is_expected.to define_enum_for(:status).with_values(pending: 0, paid: 1, failed: 2) }
  it { is_expected.to validate_numericality_of(:total_cents).is_greater_than_or_equal_to(0) }
end
```

Create `spec/models/order_item_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe OrderItem, type: :model do
  it { is_expected.to belong_to(:order) }
  it { is_expected.to belong_to(:product) }
  it { is_expected.to validate_presence_of(:product_name) }
  it { is_expected.to validate_numericality_of(:unit_price_cents).is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0).only_integer }

  it "keeps its snapshot even after the product's price changes" do
    product = create(:product, price_cents: 1000)
    item = create(:order_item, product: product, unit_price_cents: 1000)

    product.update!(price_cents: 5000)

    expect(item.reload.unit_price_cents).to eq(1000)
  end
end
```

- [ ] **Step 3: Run and confirm it fails**

Run: `bundle exec rspec spec/models/order_spec.rb spec/models/order_item_spec.rb`
Expected: FAIL — no validations/associations/enum yet.

- [ ] **Step 4: Implement `Order`**

Create `app/models/order.rb`:
```ruby
class Order < ApplicationRecord
  belongs_to :user
  has_many :order_items, dependent: :destroy

  enum :status, { pending: 0, paid: 1, failed: 2 }, default: :pending

  validates :total_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
```

- [ ] **Step 5: Implement `OrderItem`**

Create `app/models/order_item.rb`:
```ruby
class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :product_name, presence: true
  validates :unit_price_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
```

- [ ] **Step 6: Run and confirm it passes**

Run: `bundle exec rspec spec/models/order_spec.rb spec/models/order_item_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/order.rb app/models/order_item.rb \
  spec/factories/orders.rb spec/factories/order_items.rb spec/models/order_spec.rb spec/models/order_item_spec.rb
git commit -m "Add Order/OrderItem models with status enum and line-item snapshots"
```

---

## Task 13: CheckoutService — happy path

**Files:**
- Create: `app/services/checkout_service.rb`
- Create: `spec/services/checkout_service_spec.rb`

**Interfaces:**
- Consumes: `Cart`/`CartItem` (Task 8), `Product` (Task 5), `PaymentCard` (Task 11), `Order`/`OrderItem` (Task 12).
- Produces: `CheckoutService.new(user:, card_number:).call` → `CheckoutService::Result` (`success?`, `order`, `error`). This is the type every later checkout task (14, 15, 16, 17) relies on.

- [ ] **Step 1: Write the failing service spec (happy path)**

Create `spec/services/checkout_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe CheckoutService do
  describe "a successful checkout" do
    it "pays the order, deducts the card, decrements stock, and clears the cart" do
      user = create(:user)
      product = create(:product, price_cents: 1000, stock_quantity: 5)
      user.cart.cart_items.create!(product: product, quantity: 2)
      card = create(:payment_card, balance_cents: 5000)

      result = described_class.new(user: user, card_number: card.card_number).call

      expect(result).to be_success
      expect(result.order).to be_paid
      expect(result.order.total_cents).to eq(2000)
      expect(result.order.card_last4).to eq(card.card_number.last(4))
      expect(result.order.order_items.sole).to have_attributes(
        product_name: product.name, unit_price_cents: 1000, quantity: 2
      )

      expect(card.reload.balance_cents).to eq(3000)
      expect(product.reload.stock_quantity).to eq(3)
      expect(user.cart.cart_items.count).to eq(0)
    end

    it "sanitizes whitespace and dashes in the card number before matching" do
      user = create(:user)
      product = create(:product, price_cents: 1000, stock_quantity: 5)
      user.cart.cart_items.create!(product: product, quantity: 1)
      card = create(:payment_card, card_number: "4242424242424242", balance_cents: 5000)

      result = described_class.new(user: user, card_number: " 4242-4242-4242-4242 ").call

      expect(result).to be_success
      expect(result.order.card_last4).to eq("4242")
    end
  end
end
```

- [ ] **Step 2: Run and confirm it fails**

Run: `bundle exec rspec spec/services/checkout_service_spec.rb`
Expected: FAIL — `uninitialized constant CheckoutService`.

- [ ] **Step 3: Implement `CheckoutService`**

Create `app/services/checkout_service.rb`:
```ruby
# Runs a checkout against our own simulated PaymentCard wallet — never a
# real bank or payment processor. See the "Checkout flow & payment
# simulation" section of docs/superpowers/specs/2026-09-08-online-store-design.md.
class CheckoutService
  Result = Struct.new(:success?, :order, :error, keyword_init: true)

  def initialize(user:, card_number:)
    @user = user
    @card_number = card_number
  end

  def call
    abort_reason = nil

    result = ActiveRecord::Base.transaction do
      cart = @user.cart
      cart.lock!

      cart_items = cart.cart_items.includes(:product).to_a
      if cart_items.empty?
        abort_reason = "empty_cart"
        raise ActiveRecord::Rollback
      end

      products = Product.lock.where(id: cart_items.map(&:product_id)).order(:id).index_by(&:id)

      out_of_stock = cart_items.find { |item| products.fetch(item.product_id).stock_quantity < item.quantity }
      if out_of_stock
        abort_reason = "out_of_stock"
        raise ActiveRecord::Rollback
      end

      order = @user.orders.create!(status: :pending, total_cents: 0)
      total_cents = cart_items.sum { |item| products.fetch(item.product_id).price_cents * item.quantity }

      cart_items.each do |item|
        product = products.fetch(item.product_id)
        order.order_items.create!(
          product: product,
          product_name: product.name,
          unit_price_cents: product.price_cents,
          quantity: item.quantity
        )
      end
      order.update!(total_cents: total_cents)

      sanitized_card_number = @card_number.to_s.gsub(/[\s-]/, "")

      if sanitized_card_number.blank? || !sanitized_card_number.match?(/\A\d+\z/)
        order.update!(status: :failed, failure_reason: "invalid_card")
        next Result.new(success?: false, order: order, error: "invalid_card")
      end

      card = PaymentCard.find_by(card_number: sanitized_card_number)

      if card.nil?
        order.update!(status: :failed, failure_reason: "invalid_card")
        next Result.new(success?: false, order: order, error: "invalid_card")
      end

      if card.balance_cents < total_cents
        order.update!(status: :failed, failure_reason: "insufficient_funds")
        next Result.new(success?: false, order: order, error: "insufficient_funds")
      end

      card.update!(balance_cents: card.balance_cents - total_cents)
      cart_items.each do |item|
        product = products.fetch(item.product_id)
        product.update!(stock_quantity: product.stock_quantity - item.quantity)
      end
      order.update!(status: :paid, card_last4: sanitized_card_number.last(4))
      cart.cart_items.destroy_all

      Result.new(success?: true, order: order, error: nil)
    end

    result || Result.new(success?: false, order: nil, error: abort_reason)
  end
end
```

- [ ] **Step 4: Run and confirm it passes**

Run: `bundle exec rspec spec/services/checkout_service_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/checkout_service.rb spec/services/checkout_service_spec.rb
git commit -m "Add CheckoutService happy path: lock, snapshot, deduct, clear cart"
```

---

## Task 14: CheckoutService — failure paths

**Files:**
- Modify: `spec/services/checkout_service_spec.rb`

**Interfaces:**
- Consumes: `CheckoutService` (Task 13).
- Produces: no new interface — verifies every failure branch already implemented in Task 13's `#call`.

- [ ] **Step 1: Write the failing specs for every failure branch**

Add to `spec/services/checkout_service_spec.rb` (new top-level `describe` blocks, alongside the existing "a successful checkout" block):

```ruby
  describe "insufficient funds" do
    it "fails the order, leaves the cart intact, and does not touch stock or balance" do
      user = create(:user)
      product = create(:product, price_cents: 1000, stock_quantity: 5)
      user.cart.cart_items.create!(product: product, quantity: 2)
      card = create(:payment_card, balance_cents: 100)

      result = described_class.new(user: user, card_number: card.card_number).call

      expect(result).not_to be_success
      expect(result.error).to eq("insufficient_funds")
      expect(result.order).to be_failed
      expect(result.order.failure_reason).to eq("insufficient_funds")
      expect(card.reload.balance_cents).to eq(100)
      expect(product.reload.stock_quantity).to eq(5)
      expect(user.cart.cart_items.count).to eq(1)
    end
  end

  describe "invalid card" do
    it "fails the order when no card matches the number" do
      user = create(:user)
      user.cart.cart_items.create!(product: create(:product), quantity: 1)

      result = described_class.new(user: user, card_number: "0000000000000000").call

      expect(result).not_to be_success
      expect(result.error).to eq("invalid_card")
      expect(result.order).to be_failed
      expect(result.order.failure_reason).to eq("invalid_card")
    end
  end

  describe "malformed card numbers" do
    ["", "    ", "abcd1234abcd1234"].each do |bad_number|
      it "fails gracefully as invalid_card for #{bad_number.inspect} instead of raising" do
        user = create(:user)
        user.cart.cart_items.create!(product: create(:product), quantity: 1)

        result = nil
        expect { result = described_class.new(user: user, card_number: bad_number).call }.not_to raise_error

        expect(result).not_to be_success
        expect(result.error).to eq("invalid_card")
        expect(result.order.failure_reason).to eq("invalid_card")
      end
    end
  end

  describe "empty cart" do
    it "fails without creating an order" do
      user = create(:user)
      card = create(:payment_card, balance_cents: 100_000)

      result = described_class.new(user: user, card_number: card.card_number).call

      expect(result).not_to be_success
      expect(result.error).to eq("empty_cart")
      expect(result.order).to be_nil
      expect(Order.count).to eq(0)
    end
  end

  describe "out of stock" do
    it "fails without creating an order and without touching stock" do
      user = create(:user)
      product = create(:product, stock_quantity: 1)
      user.cart.cart_items.create!(product: product, quantity: 5)
      card = create(:payment_card, balance_cents: 100_000)

      result = described_class.new(user: user, card_number: card.card_number).call

      expect(result).not_to be_success
      expect(result.error).to eq("out_of_stock")
      expect(result.order).to be_nil
      expect(Order.count).to eq(0)
      expect(product.reload.stock_quantity).to eq(1)
    end
  end
```

- [ ] **Step 2: Run and confirm every new example passes without changing implementation**

Run: `bundle exec rspec spec/services/checkout_service_spec.rb`
Expected: PASS — Task 13's implementation already handles every branch; this task exists to lock in that coverage with its own reviewable commit, per the spec's testing-strategy requirement to explicitly cover each failure path.

- [ ] **Step 3: Commit**

```bash
git add spec/services/checkout_service_spec.rb
git commit -m "Cover CheckoutService failure paths: insufficient funds, invalid/malformed card, empty cart, out of stock"
```

---

## Task 15: CheckoutService — double-checkout race spec

**Files:**
- Modify: `Gemfile`
- Modify: `spec/rails_helper.rb`
- Create: `spec/services/checkout_service_race_spec.rb`

**Interfaces:**
- Consumes: `CheckoutService` (Task 13).
- Produces: no new interface — a dedicated, isolated spec proving the cart-row lock from Task 13 prevents a double-checkout race. Tagged `:race_condition`, excluded from the default run (configured in Task 1).

- [ ] **Step 1: Add `database_cleaner-active_record`**

Add to the `group :test do` block in `Gemfile`:
```ruby
gem "database_cleaner-active_record"
```
Run: `bundle install`

- [ ] **Step 2: Write the race-condition spec**

Create `spec/services/checkout_service_race_spec.rb`:
```ruby
require "rails_helper"
require "database_cleaner/active_record"

RSpec.describe CheckoutService, "double-checkout race", :race_condition, type: :model do
  self.use_transactional_tests = false

  before { DatabaseCleaner.strategy = :truncation }
  after { DatabaseCleaner.clean }

  it "allows only one of two concurrent checkouts against the same cart to succeed" do
    user = create(:user)
    product = create(:product, price_cents: 1000, stock_quantity: 5)
    user.cart.cart_items.create!(product: product, quantity: 1)
    card = create(:payment_card, balance_cents: 100_000)

    results = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          results << CheckoutService.new(user: user, card_number: card.card_number).call
        end
      end
    end
    threads.each(&:join)

    outcomes = Array.new(2) { results.pop }

    expect(outcomes.count(&:success?)).to eq(1)
    expect(Order.where(user: user, status: :paid).count).to eq(1)
    expect(product.reload.stock_quantity).to eq(4)
    expect(card.reload.balance_cents).to eq(99_000)
  end
end
```

This spec turns off the transactional-test wrapper (`use_transactional_tests = false`) so the two threads see each other's real, committed writes — that's the whole point of the test. Because nothing rolls back automatically, `DatabaseCleaner` truncates every table after the example so no state leaks into the rest of the (transactional) suite.

- [ ] **Step 3: Run it in isolation and confirm it passes**

Run: `bundle exec rspec spec/services/checkout_service_race_spec.rb --tag race_condition`
Expected: PASS. (Without `--tag race_condition` it won't run at all — `config.filter_run_excluding :race_condition`, set in Task 1, excludes it from the default suite.)

- [ ] **Step 4: Confirm it's excluded from the default run**

Run: `bundle exec rspec spec/services/checkout_service_race_spec.rb`
Expected: `0 examples, 0 failures` (filtered out).

- [ ] **Step 5: Confirm the rest of the suite is unaffected**

Run: `bundle exec rspec`
Expected: all non-race-condition examples still pass (this spec is excluded by default, as designed).

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock spec/services/checkout_service_race_spec.rb
git commit -m "Add isolated double-checkout race spec (tag :race_condition)"
```

---

## Task 16: OrderPolicy

**Files:**
- Create: `app/policies/order_policy.rb`
- Create: `spec/policies/order_policy_spec.rb`

**Interfaces:**
- Consumes: `ApplicationPolicy` (Task 3), `Order` (Task 12), `User#admin?` (Task 2).
- Produces: `OrderPolicy.new(user, order).show?` and `OrderPolicy::Scope.new(user, Order).resolve`, used by `OrdersController` in Task 18.

- [ ] **Step 1: Write the failing policy spec**

Create `spec/policies/order_policy_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe OrderPolicy do
  describe "#show?" do
    it "allows the order's owner and any admin, denies everyone else" do
      owner = create(:user)
      admin = create(:user, :admin)
      other = create(:user)
      order = create(:order, user: owner)

      expect(described_class.new(owner, order).show?).to be true
      expect(described_class.new(admin, order).show?).to be true
      expect(described_class.new(other, order).show?).to be false
      expect(described_class.new(nil, order).show?).to be false
    end
  end

  describe "Scope" do
    it "restricts regular users to their own orders and lets admins see all" do
      owner = create(:user)
      admin = create(:user, :admin)
      order = create(:order, user: owner)
      other_order = create(:order)

      expect(described_class::Scope.new(owner, Order).resolve).to contain_exactly(order)
      expect(described_class::Scope.new(admin, Order).resolve).to include(order, other_order)
    end
  end
end
```

- [ ] **Step 2: Run and confirm it fails**

Run: `bundle exec rspec spec/policies/order_policy_spec.rb`
Expected: FAIL — `uninitialized constant OrderPolicy`.

- [ ] **Step 3: Implement `OrderPolicy`**

Create `app/policies/order_policy.rb`:
```ruby
class OrderPolicy < ApplicationPolicy
  def show?
    user.present? && (user.admin? || record.user_id == user.id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.admin? ? scope.all : scope.where(user_id: user.id)
    end
  end
end
```

- [ ] **Step 4: Run and confirm it passes**

Run: `bundle exec rspec spec/policies/order_policy_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/policies/order_policy.rb spec/policies/order_policy_spec.rb
git commit -m "Add OrderPolicy: owner-or-admin show, scoped index"
```

---

## Task 17: CheckoutsController and checkout view

**Files:**
- Create: `app/controllers/checkouts_controller.rb`
- Create: `app/views/checkouts/new.html.erb`
- Create: `spec/requests/checkouts_spec.rb`

**Interfaces:**
- Consumes: `CheckoutService` (Tasks 13-15), `Cart` (Task 8), `PaymentCard` (Task 11).
- Produces: `GET /checkout/new`, `POST /checkout`.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/checkouts_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Checkout", type: :request do
  def sign_in_with_cart(quantity: 1, product_stock: 10, product_price_cents: 1000)
    user = create(:user)
    product = create(:product, stock_quantity: product_stock, price_cents: product_price_cents)
    user.cart.cart_items.create!(product: product, quantity: quantity)
    sign_in user
    [user, product]
  end

  it "requires sign in" do
    post checkout_path, params: { card_number: "4242424242424242" }
    expect(response).to redirect_to(new_user_session_path)
  end

  it "succeeds with a valid, sufficiently funded card" do
    card = create(:payment_card, balance_cents: 100_000)
    user, = sign_in_with_cart

    post checkout_path, params: { card_number: card.card_number }

    order = user.orders.last
    expect(order).to be_paid
    expect(response).to redirect_to(order_path(order))
  end

  it "fails with insufficient funds and leaves the cart intact" do
    card = create(:payment_card, balance_cents: 1)
    user, = sign_in_with_cart

    post checkout_path, params: { card_number: card.card_number }

    order = user.orders.last
    expect(order).to be_failed
    expect(order.failure_reason).to eq("insufficient_funds")
    expect(user.cart.cart_items.count).to eq(1)
  end

  it "fails with a card number that doesn't exist" do
    user, = sign_in_with_cart

    post checkout_path, params: { card_number: "0000000000000000" }

    expect(user.orders.last.failure_reason).to eq("invalid_card")
  end

  it "fails gracefully instead of erroring on a malformed card number" do
    user, = sign_in_with_cart

    post checkout_path, params: { card_number: "abcd-not-a-card" }

    expect(response).to have_http_status(:redirect)
    expect(user.orders.last.failure_reason).to eq("invalid_card")
  end

  it "rejects checkout with an empty cart" do
    user = create(:user)
    card = create(:payment_card, balance_cents: 100_000)
    sign_in user

    expect { post checkout_path, params: { card_number: card.card_number } }.not_to change(Order, :count)
  end

  it "fails when the cart quantity exceeds available stock" do
    card = create(:payment_card, balance_cents: 100_000)
    user, product = sign_in_with_cart(quantity: 5, product_stock: 2)

    expect { post checkout_path, params: { card_number: card.card_number } }.not_to change(Order, :count)
    expect(product.reload.stock_quantity).to eq(2)
  end
end
```

- [ ] **Step 2: Run and confirm it fails**

Run: `bundle exec rspec spec/requests/checkouts_spec.rb`
Expected: FAIL — no `CheckoutsController` yet.

- [ ] **Step 3: Implement `CheckoutsController`**

Create `app/controllers/checkouts_controller.rb`:
```ruby
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
```

- [ ] **Step 4: Implement the checkout view**

Create `app/views/checkouts/new.html.erb`:
```erb
<h1>Checkout</h1>

<p>This is a <strong>simulated</strong> payment. Use one of the seeded test card numbers below.</p>
<ul class="test-card-list">
  <% PaymentCard.order(:card_number).each do |card| %>
    <li><%= card.card_number %> &mdash; balance $<%= "%.2f" % (card.balance_cents / 100.0) %></li>
  <% end %>
</ul>

<p>Your cart total: $<%= "%.2f" % (current_user.cart.total_cents / 100.0) %></p>

<%= form_with url: checkout_path, method: :post, class: "checkout-form" do %>
  <div class="field">
    <%= label_tag :card_number, "Card number" %>
    <%= text_field_tag :card_number, nil, placeholder: "4242 4242 4242 4242" %>
  </div>
  <%= submit_tag "Pay", class: "btn btn--accent btn--large" %>
<% end %>
```

(Listing the seeded card numbers directly on the checkout page is intentional — this is a fake payment simulation, not a real one, so there's no secret to protect, and it's what makes the demo usable without a separate lookup.)

- [ ] **Step 5: Run and confirm it passes**

Run: `bundle exec rspec spec/requests/checkouts_spec.rb`
Expected: PASS, all examples green.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/checkouts_controller.rb app/views/checkouts spec/requests/checkouts_spec.rb
git commit -m "Add checkout endpoint wiring CheckoutService to the cart"
```

---

## Task 18: OrdersController and order views

**Files:**
- Create: `app/controllers/orders_controller.rb`
- Create: `app/views/orders/index.html.erb`, `show.html.erb`
- Create: `spec/requests/orders_spec.rb`

**Interfaces:**
- Consumes: `Order`/`OrderItem` (Task 12), `OrderPolicy` (Task 16).
- Produces: `GET /orders`, `GET /orders/:id`.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/orders_spec.rb`:
```ruby
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
```

- [ ] **Step 2: Run and confirm it fails**

Run: `bundle exec rspec spec/requests/orders_spec.rb`
Expected: FAIL — no `OrdersController` yet.

- [ ] **Step 3: Implement `OrdersController`**

Create `app/controllers/orders_controller.rb`:
```ruby
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
```

- [ ] **Step 4: Implement the views**

Create `app/views/orders/index.html.erb`:
```erb
<h1><%= current_user.admin? ? "All Orders" : "My Orders" %></h1>

<% if @orders.empty? %>
  <p>No orders yet.</p>
<% else %>
  <table class="orders-table">
    <thead>
      <tr><th>Order</th><th>Status</th><th>Total</th><th>Placed</th><th></th></tr>
    </thead>
    <tbody>
      <% @orders.each do |order| %>
        <tr>
          <td>#<%= order.id %></td>
          <td><span class="status-badge status-badge--<%= order.status %>"><%= order.status %></span></td>
          <td>$<%= "%.2f" % (order.total_cents / 100.0) %></td>
          <td><%= order.created_at.strftime("%b %-d, %Y") %></td>
          <td><%= link_to "View", order_path(order) %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
```

Create `app/views/orders/show.html.erb`:
```erb
<h1>Order #<%= @order.id %></h1>
<p><span class="status-badge status-badge--<%= @order.status %>"><%= @order.status %></span></p>

<% if @order.failed? %>
  <p class="flash flash--alert">
    Payment failed:
    <%= @order.failure_reason == "insufficient_funds" ? "insufficient funds on the card." : "invalid card number." %>
  </p>
<% end %>

<% if @order.paid? %>
  <p>Paid with card ending in <%= @order.card_last4 %>.</p>
<% end %>

<table class="order-items-table">
  <thead><tr><th>Product</th><th>Unit price</th><th>Quantity</th><th>Subtotal</th></tr></thead>
  <tbody>
    <% @order.order_items.each do |item| %>
      <tr>
        <td><%= item.product_name %></td>
        <td>$<%= "%.2f" % (item.unit_price_cents / 100.0) %></td>
        <td><%= item.quantity %></td>
        <td>$<%= "%.2f" % (item.unit_price_cents * item.quantity / 100.0) %></td>
      </tr>
    <% end %>
  </tbody>
</table>

<p class="cart-total">Total: $<%= "%.2f" % (@order.total_cents / 100.0) %></p>
```

- [ ] **Step 5: Run and confirm it passes**

Run: `bundle exec rspec spec/requests/orders_spec.rb`
Expected: PASS, all examples green.

- [ ] **Step 6: Confirm the full suite still passes**

Run: `bundle exec rspec`
Expected: every non-race-condition example green.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/orders_controller.rb app/views/orders spec/requests/orders_spec.rb
git commit -m "Add order history: policy-scoped index, owner-or-admin show"
```

---

## Task 19: Seed data

**Files:**
- Create: `db/seeds.rb`

**Interfaces:**
- Consumes: `User`, `Product`, `PaymentCard` (Tasks 2, 5, 11).
- Produces: a runnable `bin/rails db:seed` that gives a fresh checkout of this app something to click through immediately.

- [ ] **Step 1: Write `db/seeds.rb`**

```ruby
# This app's checkout is a SIMULATION — no real bank or card network is
# ever contacted. The PaymentCards below are our own fake wallet records,
# not real card numbers. See docs/superpowers/specs/2026-09-08-online-store-design.md.

admin = User.find_or_create_by!(email: "admin@example.com") do |user|
  user.password = "password123"
  user.password_confirmation = "password123"
  user.role = :admin
end
puts "Admin: #{admin.email} / password123"

[
  { card_number: "4242424242424242", holder_name: "Ada Lovelace", balance_cents: 10_000 },
  { card_number: "4000000000000002", holder_name: "Grace Hopper", balance_cents: 500 },
  { card_number: "4000000000000010", holder_name: "Empty Wallet", balance_cents: 0 }
].each do |attrs|
  PaymentCard.find_or_create_by!(card_number: attrs[:card_number]) do |card|
    card.holder_name = attrs[:holder_name]
    card.balance_cents = attrs[:balance_cents]
  end
end
puts "Seeded #{PaymentCard.count} test payment cards (see README for the full list)."

products = [
  { name: "Simple Way Of Peace Life", description: "A calm, practical guide to slowing down.", price_cents: 4000, stock_quantity: 12 },
  { name: "Great Travel At Desert", description: "A memoir of crossing the Sahara on foot.", price_cents: 3800, stock_quantity: 8 },
  { name: "The Lady Beauty Scarlett", description: "A gothic novel set in Victorian London.", price_cents: 4500, stock_quantity: 0 },
  { name: "The Hypocrite World", description: "A satirical look at Silicon Valley culture.", price_cents: 3200, stock_quantity: 20 }
]

products.each do |attrs|
  Product.find_or_create_by!(name: attrs[:name]) do |product|
    product.description = attrs[:description]
    product.price_cents = attrs[:price_cents]
    product.stock_quantity = attrs[:stock_quantity]
  end
end
puts "Seeded #{Product.count} products."
```

- [ ] **Step 2: Run it**

Run: `bin/rails db:seed`
Expected: prints the admin credentials and seed counts, no errors. Run twice in a row to confirm it's idempotent (no duplicate-key errors on the second run).

- [ ] **Step 3: Commit**

```bash
git add db/seeds.rb
git commit -m "Add seed data: admin user, test payment cards, sample products"
```

---

## Task 20: Self-review — authorization, N+1, and validation audit

**Files:** none created; this task reviews and, if needed, patches files from every earlier task.

- [ ] **Step 1: Authorization audit**

Run: `grep -rn "def \(create\|update\|destroy\|show\|index\)" app/controllers`

For every action listed, confirm it does one of:
- calls `authorize` or `policy_scope` (Pundit), or
- is a Devise-generated controller (out of scope for Pundit — Devise handles its own access rules), or
- is intentionally public (`ProductsController#index`/`#show`, which call `authorize Product`/`authorize @product` against a policy that returns `true` for everyone — still authorized, just permissively).

Confirm every controller that calls `authorize`/`policy_scope` at all (`ProductsController`, `CartItemsController`, `OrdersController`) does so in **every** action, not just some — a partially-covered controller is a common way to leave one action unintentionally open. If any action is missing a call, add it now and re-run that controller's request spec to confirm the corresponding 403 case is actually covered; if it isn't, add the missing case.

- [ ] **Step 2: N+1 query audit**

Run the full suite with query logging on to eyeball for repeated queries in a loop. Wrap it in a transaction that always rolls back — this runs against the shared `test` database outside of RSpec's per-example rollback, so without an explicit rollback it would permanently leave an "audit@example.com" user and three "Audit N" products in the test database for every later spec run to trip over:
```bash
RAILS_ENV=test bin/rails runner "
ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.transaction do
  user = User.create!(email: 'audit@example.com', password: 'password123')
  3.times { |i| p = Product.create!(name: \"Audit \#{i}\", price_cents: 100, stock_quantity: 1); user.cart.cart_items.create!(product: p, quantity: 1) }
  puts '--- cart total_cents ---'
  user.cart.total_cents
  puts '--- cart_items view render pattern (product access) ---'
  user.cart.cart_items.includes(:product).each { |ci| ci.product.name }
  raise ActiveRecord::Rollback
end
"
```

Confirm:
- `Cart#total_cents` issues exactly one query (it uses `joins` + SQL `sum`, not a Ruby loop over `.product.price_cents` — verify the logged SQL is a single `SELECT SUM(...)`).
- The cart items view (`app/views/carts/show.html.erb`) already calls `.includes(:product)` (Task 10, Step 5) — confirm the log shows one `products` query, not N.
- `app/views/orders/show.html.erb` iterates `@order.order_items` — these don't need `.product`, only the snapshot columns (`product_name`, `unit_price_cents`), so no N+1 risk there; confirm no `.product` calls were introduced.
- `app/views/products/index.html.erb` calls `product.image.attached?` per product in the grid — Active Storage's `attached?` check is a single preloadable association; if a real product catalog grew large this would N+1 on attachments. For this app's scope (a handful of seeded products, per the spec's YAGNI stance on inventory tooling) this is acceptable as-is; note it in the commit message rather than adding `with_attached_image` scoping that nothing in the spec asked for.

If any unexpected N+1 turns up (a query count that scales with the number of records rather than staying constant), fix it with `.includes(...)` at the call site and re-run the relevant request spec.

- [ ] **Step 3: Validation gap audit**

Re-read every model's validations against the spec's data model table (`docs/superpowers/specs/2026-09-08-online-store-design.md`, "Data model" section) column by column:
- `users.role` — enum with default, covered (Task 2).
- `products.name/price_cents/stock_quantity` — presence/numericality, covered (Task 5). `description` and `image` are optional per spec — confirm no validation was accidentally added for either.
- `carts.user_id` — uniqueness enforced at the DB index level (Task 8); Rails doesn't also need a model-level `validates :user_id, uniqueness: true` here since a cart is only ever created once via `after_create` — confirm no code path creates a second `Cart` for a `User` directly (grep: `grep -rn "Cart.create\|Cart.new" app/`, expect no matches outside `User#create_default_cart`).
- `cart_items.quantity/product_id` — numericality + scoped uniqueness, covered (Task 8).
- `orders.status/total_cents/card_last4/failure_reason` — enum + numericality covered (Task 12); `card_last4`/`failure_reason` are correctly nullable (only set on paid/failed respectively) — confirm no presence validation was mistakenly added to either.
- `order_items.product_name/unit_price_cents/quantity` — covered (Task 12).
- `payment_cards.card_number/balance_cents` — presence/uniqueness/numericality, covered (Task 11).

If any column above is missing its validation, add it now with a failing-then-passing spec in that model's spec file, following the same RED-GREEN pattern as its original task.

- [ ] **Step 4: Run the full suite one more time**

Run: `bundle exec rspec`
Expected: all examples green (race-condition spec excluded by default, as designed).

Run: `bundle exec rspec --tag race_condition`
Expected: the race spec passes on its own.

- [ ] **Step 5: Commit (only if Steps 1-3 produced changes)**

```bash
git add -A
git commit -m "Self-review: close any authorization/N+1/validation gaps found in audit"
```

If the audit found nothing to fix, skip this commit — there's nothing to record.

---

## Task 21: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write the README**

Replace the contents of `README.md`:
```markdown
# Shop Trololo

A small online store built with Rails, Devise, and Pundit.

## ⚠️ This payment system is a simulation

**No real payment gateway, bank, or card network is ever contacted.**
Checkout runs entirely against our own `PaymentCard` model — a fake
wallet seeded with test card numbers and balances (see `db/seeds.rb`).
Do not point this at real card numbers; it wouldn't do anything with
them except fail to find a match. See `app/services/checkout_service.rb`
and `docs/superpowers/specs/2026-09-08-online-store-design.md` for the
full design.

## Setup

1. Make sure PostgreSQL is running locally (e.g. `brew services start postgresql@16`).
2. `bundle install`
3. `bin/rails db:create db:migrate db:seed`
4. `bin/rails server`

Seeding creates an admin login (`admin@example.com` / `password123`)
and a few test payment cards:

| Card number | Balance | Use it to test |
|---|---|---|
| `4242424242424242` | $100.00 | A successful checkout |
| `4000000000000002` | $5.00 | An insufficient-funds failure |
| `4000000000000010` | $0.00 | An insufficient-funds failure |
| (anything else) | — | An invalid-card failure |

## Running the tests

```bash
bundle exec rspec
```

One spec is excluded from the default run: a double-checkout race-condition
test that opens two real concurrent database connections. It's slower and
more resource-sensitive than the rest of the suite, so it's tagged and run
separately:

```bash
bundle exec rspec --tag race_condition
```

## Roles

- **admin** — full product CRUD (including inventory/stock), can view
  every order.
- **user** (default on sign-up) — browses products, manages their own
  cart, checks out, and views their own order history.

There's no public "sign up as admin" — the only admin account is the
one created by `db/seeds.rb` (or via `rails console`).

## Visual design

The layout's palette, typography, and a few page layouts (product
listing/cards, header/footer) are loosely adapted from a Figma
"Book store template" community file, reviewed as a style reference
rather than implemented pixel-for-pixel. See the "Visual design"
section of `docs/superpowers/specs/2026-09-08-online-store-design.md`
for what was and wasn't carried over.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Write README: simulation disclaimer, setup, test cards, race-spec instructions"
```

---

## Plan self-review notes

- **Spec coverage:** every section of the spec maps to a task — data model (Tasks 2, 5, 8, 11, 12), authorization (Tasks 3, 6, 9, 16), routes/controllers (Tasks 7, 10, 17, 18), checkout flow + stock-at-checkout-only + race handling (Tasks 13-15), testing strategy's five categories (model/request/policy/image/race specs are each present in their owning task), setup changes (Tasks 1, 2, 5 for Active Storage confirmation, 15 for the DB pool), and visual design (Tasks 4, 7, 10, 17, 18 for CSS/layout).
- **Active Storage service config:** the scaffolded app already sets `config.active_storage.service = :local` for development/production and `:test` for test (confirmed by reading the generated environment files before writing this plan) — Task 5 only needs to run the installer, not add new environment config. Task 5's commit message and this note stand in for a separate config task the spec's clarification asked for; nothing further was needed.
- **Type consistency check:** `CheckoutService::Result` (`success?`, `order`, `error`) as defined in Task 13 is used identically in Tasks 14, 15, and 17 — no renamed fields. `Product.sorted(key)` (Task 5) is called with the same string keys (`"name_asc"` etc.) in Task 7's controller and view. `Cart#total_cents` (Task 8) is used with that exact name in Tasks 10, 13, and 17.
- **Route-before-controller ordering:** Task 2 defines the complete `config/routes.rb` before most controllers exist. This is safe — Rails resolves a route's controller only when a request is dispatched to it, not at boot or when a view calls a path helper — and is called out explicitly in Task 2 so the implementer doesn't "fix" it by reordering.
