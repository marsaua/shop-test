# Online Store — Design Spec

Date: 2026-09-08
Status: Approved by user, pending implementation plan

## Summary

A server-rendered Rails online store with Devise authentication, Pundit
authorization, and a fully simulated payment backend (no real payment
gateway). Two roles: `admin` (manages products/inventory, views all
orders) and `user` (browses, manages their own cart, checks out, views
own order history). Unauthenticated visitors can browse products but
must log in to add to cart or check out.

**This project does not integrate with any real payment processor.**
`PaymentCard` is our own model seeded with fake test card numbers and
balances, purely to exercise a realistic checkout flow (success,
insufficient funds, invalid card) without touching real money or PII.
This must be stated clearly in the README and in code comments near
the payment logic.

## Stack

- Ruby on Rails 8.1 (already scaffolded), Ruby 3.3.9
- PostgreSQL (replacing the default SQLite scaffold)
- Devise (authentication), Pundit (authorization)
- RSpec + FactoryBot + Shoulda Matchers (replacing default Minitest)
- Faker (test/seed data only)
- Server-rendered HTML views (Turbo/Stimulus already in the Gemfile),
  classic Rails forms + redirects — no Turbo Streams/SPA behavior
- Active Storage for the optional product image (`image_processing`
  gem is already present in the generated Gemfile)

## Data model

Money is stored as integer cents throughout (`price_cents`,
`total_cents`, `balance_cents`) to avoid float rounding issues.

### `users` (Devise + role)

| column | type | notes |
|---|---|---|
| (Devise fields) | | email, encrypted_password, etc. |
| role | integer | enum `{ user: 0, admin: 1 }`, default: `user`, not null |

Role is a plain enum column, **not** a separate roles table: only two
fixed roles, no need for dynamic/many-to-many role assignment, and
Pundit policies read cleanly off `user.admin?`. There is no public
"sign up as admin" — admin accounts are created via `db/seeds.rb` or
`rails console` only.

### `products`

| column | type | notes |
|---|---|---|
| name | string | not null |
| description | text | |
| price_cents | integer | not null |
| stock_quantity | integer | not null, default: 0 |
| (image) | Active Storage | `has_one_attached :image`, optional |

"Manage inventory" is implemented as editing `stock_quantity` through
the normal admin Product form — no separate inventory/audit-log model.

### `carts`

| column | type | notes |
|---|---|---|
| user_id | references | not null, unique index (one persistent cart per user) |

### `cart_items`

| column | type | notes |
|---|---|---|
| cart_id | references | not null |
| product_id | references | not null |
| quantity | integer | not null, default: 1, must be >= 1 |

Unique index on `[cart_id, product_id]` — adding the same product
again increments quantity rather than creating a duplicate row.

### `orders`

| column | type | notes |
|---|---|---|
| user_id | references | not null |
| status | integer | enum `{ pending: 0, paid: 1, failed: 2 }`, default: `pending` |
| total_cents | integer | not null, snapshot of cart total at checkout |
| card_last4 | string | set once paid |
| failure_reason | string | `"invalid_card"` \| `"insufficient_funds"`, set if failed |

`pending` is a transient state during the checkout transaction; in
this synchronous flow every checkout resolves to `paid` or `failed`
within the same request, so `pending` is not expected to be observed
as a lasting state. (If a future requirement needs a real
"awaiting payment" state — e.g. an async payment step — this would
need revisiting.)

### `order_items` (snapshot of cart at purchase time)

| column | type | notes |
|---|---|---|
| order_id | references | not null |
| product_id | references | not null |
| product_name | string | not null, snapshotted |
| unit_price_cents | integer | not null, snapshotted |
| quantity | integer | not null |

Snapshotting `product_name`/`unit_price_cents` means later edits to
the product (price changes, renames) never alter historical orders.

### `payment_cards` (global seeded test cards — NOT tied to a user)

| column | type | notes |
|---|---|---|
| card_number | string | not null, unique index |
| holder_name | string | |
| balance_cents | integer | not null, default: 0 |

Any logged-in user may attempt checkout with any seeded card number —
these are global test fixtures analogous to Stripe's published test
card numbers, not a per-user saved-payment-methods feature.

### Associations

- `User has_one :cart, dependent: :destroy` / `has_many :orders`
- `Cart belongs_to :user` / `has_many :cart_items, dependent: :destroy` / `has_many :products, through: :cart_items`
- `CartItem belongs_to :cart` / `belongs_to :product`
- `Product has_many :cart_items, dependent: :destroy` / `has_many :order_items, dependent: :restrict_with_error`
  (blocks deleting a product that's already been purchased, to keep
  order history intact; a product only sitting in a cart can be
  deleted freely, cascading the cart_item away)
- `Order belongs_to :user` / `has_many :order_items, dependent: :destroy`
- `OrderItem belongs_to :order` / `belongs_to :product`
- `PaymentCard` — standalone, no associations

## Authorization (Pundit)

- **ProductPolicy**: `index?`/`show?` → everyone, including guests.
  `create?`/`update?`/`destroy?` → admin only.
- **CartItemPolicy**: only the cart's owner may create/update/destroy
  their own cart items. No admin override.
- **OrderPolicy**: `show?` → owner or admin. `index?` uses a
  `policy_scope` — regular users see only their own orders, admins see
  all.
- `Pundit::NotAuthorizedError` rescued in `ApplicationController`,
  renders 403.
- `authenticate_user!` required before adding to cart, checking out,
  or viewing orders. Not required for browsing products (index/show).

## Routes / controllers

```
resources :products                         # index/show public; new/create/edit/update/destroy admin
resource  :cart, only: [:show]               # current_user's cart
resources :cart_items, only: [:create, :update, :destroy]
resource  :checkout, only: [:new, :create]   # :new = card-number form, :create = runs CheckoutService
resources :orders, only: [:index, :show]     # policy_scope'd index, owner-or-admin show
```

## Checkout flow & payment simulation

A plain service object, `CheckoutService.new(user:, card_number:).call`,
wraps the whole operation in **one DB transaction**:

1. Lock the user's `cart` row (`SELECT ... FOR UPDATE`) — this is the
   mutex for the whole operation.
2. If the cart has no items → abort, return a validation error. No
   `Order` row is created.
3. Lock every referenced `Product` row (ordered by id, to avoid
   deadlocks), check `stock_quantity >= quantity` for each line. If
   any line is short → abort, return an out-of-stock error. No
   `Order` row is created.
4. Create the `Order` (`pending`) + `order_items`, snapshotting
   `product_name` / `unit_price_cents` / `quantity` from the cart.
5. Sanitize the submitted card number: strip whitespace and any
   non-digit separators (spaces, dashes). If the sanitized value is
   empty or contains any non-digit characters, treat it the same as
   "not found" below — fail with `invalid_card` rather than raising or
   querying the database with a malformed value.
6. Look up `PaymentCard` by the sanitized card number:
   - **Not found (including malformed input from step 5)** → `order.update!(status: :failed, failure_reason: "invalid_card")`,
     commit. Cart is left intact so the user can retry with a
     different card.
   - **Found, insufficient balance** → `order.update!(status: :failed, failure_reason: "insufficient_funds")`,
     commit. Cart left intact.
   - **Found, sufficient balance** → deduct the card's balance,
     decrement each product's `stock_quantity`,
     `order.update!(status: :paid, card_last4: sanitized_card_number.last(4))`,
     clear the cart's items, commit.

### Stock is checked at checkout, not at add-to-cart

This is an intentional design decision, not an oversight: adding a
product to the cart (`CartItemsController#create`/`#update`) never
checks `stock_quantity`. Checkout (step 3 above) is the single source
of truth for stock availability. A user can add more of a product to
their cart than is currently in stock, and will only discover a
shortfall at checkout time (the existing out-of-stock failure path).
This should be reiterated as a short code comment on `CartItem` and/or
`CartItemsController` so a future contributor doesn't "fix" it by
adding a redundant stock check on add-to-cart. No new spec is needed
for this beyond the existing out-of-stock checkout request spec, which
already covers it.

### Double-checkout race

Because step 1 locks the cart row for the duration of the
transaction, a second concurrent checkout request against the same
cart blocks until the first commits (and clears the cart), then sees
an empty cart and fails cleanly at step 2 — no duplicate orders, no
double stock deduction, no double card charge.

## Testing strategy (RSpec)

- **Model specs**: validations/associations (shoulda-matchers), role
  enum, `Cart#total_cents`, `CheckoutService` payment-deduction logic
  exercised directly.
- **Request specs** per controller: auth required where needed, Pundit
  403s for non-admins on product management, cart add/update/remove,
  checkout success / insufficient funds / invalid card / empty cart /
  out-of-stock / malformed card number (letters, empty string, extra
  whitespace — confirms it fails gracefully as `invalid_card` rather
  than raising a 500).
- Product image request specs: admin can attach an image on
  create/update, and omitting the image (it's optional) is also a
  valid create/update.
- **Policy specs**: one per Pundit policy, covering guest/user/admin
  and owner-vs-not-owner combinations.
- **Race-condition spec**: two threads, each on its own DB connection,
  both invoking `CheckoutService` against the same cart concurrently.
  Rails' default transactional-test wrapper prevents real concurrency
  (both threads would share one wrapped transaction), so this spec
  needs `use_transactional_tests = false` (or DatabaseCleaner
  truncation), with an explicit teardown step that truncates the
  affected tables afterward so it doesn't leak state into the
  transactional suite. Tagged `:race_condition` and excluded from the
  default run; documented in the README as runnable in isolation via
  `bundle exec rspec --tag race_condition`, since it may be
  slower/flakier than the rest of the suite under CI resource
  constraints.

## Setup changes from the current scaffold

- Swap `sqlite3` → `pg` in `Gemfile` and `config/database.yml` for
  dev/test/prod.
- Add gems: `devise`, `pundit`, `rspec-rails`, `factory_bot_rails`,
  `shoulda-matchers`, `faker` (test/seed data only).
- Remove the default Minitest `test/` directory in favor of `spec/`.
- In `config/database.yml`, increase `pool` for the `test` environment
  to at least 5 (default is `ENV.fetch("RAILS_MAX_THREADS") { 5 }`,
  but confirm/pin it explicitly) so the two concurrent threads in the
  race-condition spec don't block waiting for a connection from
  ActiveRecord's connection pool.
- `db/seeds.rb`: a handful of `PaymentCard`s with clearly fake numbers
  and a mix of balances (including a zero/low-balance one to exercise
  the insufficient-funds path), a few sample `Product`s, one seeded
  admin `User`.
- Active Storage service per environment, set explicitly rather than
  left on the generator default:
  - `development` and `test`: `:local` disk service in
    `config/storage.yml`, explicitly referenced in
    `config/environments/development.rb` and `test.rb`
    (`config.active_storage.service = :local`).
  - `production`: also `:local` disk for this project's scope (no
    S3/cloud bucket setup required) — with a comment in
    `config/storage.yml` noting a real deployment would swap this for
    a cloud service, since local disk storage doesn't persist across
    container redeploys or multiple app instances.
- README: a prominent section stating this payment system is a
  simulation only, not a real payment integration, with pointers to
  the seeded test card numbers; plus the race-condition-spec run
  instructions noted in the testing strategy above.

## Visual design

A "Book store template" Figma community file
(https://www.figma.com/design/JjkDUl3BDrISV5DfhDTiEF/Book-store-template--Community-)
was provided as a **style reference, not a pixel-exact target**. Figma
OAuth wasn't completed, so the file was reviewed from a downloaded
static export (flat homepage + products-listing screenshots) rather
than live design-token/component data — treat measurements as
approximate, not authoritative.

What we're drawing from it:
- **Palette**: navy (`#1B2555`-ish) for the header bar and headings,
  coral-orange (`#E85C41`-ish) for CTAs/prices/footer background, a
  soft pink→mint gradient for hero/breadcrumb bands, white cards.
- **Typography**: a bold geometric sans for headings (Poppins), a
  clean sans for body text (Inter) — both via Google Fonts.
- **Layout patterns**: utility bar + header (logo, search, account,
  cart, wishlist) and footer (3-column, orange background) reused on
  every page; a Products index with a left filter sidebar, sort
  dropdown, grid/list toggle, and pagination; product cards with a
  hover "Add to Cart" affordance, title, and price.

Scope adjustments to fit our actual data model:
- The mockup's filter sidebar has Price/Product type/Availability/
  Brand/Color/Material. Our `Product` model only has `name` /
  `description` / `price_cents` / `stock_quantity`, so only **Price
  range** and **In stock** filters are implemented — Brand/Color/
  Material don't exist in our schema and won't be added as
  non-functional UI.
- The mockup is a marketing template full of sections with no
  backend behind them (blog, newsletter signup, ebook CTA, countdown
  promo, wishlist). These are skipped entirely — we're not building
  unused decoration.
- Cart, checkout, and order-detail pages have no equivalent screen in
  the reference file; they're styled to match the same palette,
  typography, and component patterns (header/footer/buttons/cards)
  rather than left unstyled or invented from an unrelated aesthetic.

Styling approach: plain CSS with custom properties for the palette,
under `app/assets/stylesheets` — Propshaft-compatible with zero new
build tooling. No CSS framework (e.g. Tailwind) is introduced, since
the project doesn't already have one and it would be a heavier
dependency than this scope warrants.

## Out of scope / explicitly deferred

- Real payment gateway integration of any kind.
- Per-user saved payment methods / wallet.
- Turbo Streams / SPA-style cart updates — classic form + redirect
  flow only.
- Separate inventory audit-log/history model — stock is a plain
  `Product` column.
- Admin management of other users' carts.
