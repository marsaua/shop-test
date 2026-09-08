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
5. Look up `PaymentCard` by the entered card number:
   - **Not found** → `order.update!(status: :failed, failure_reason: "invalid_card")`,
     commit. Cart is left intact so the user can retry with a
     different card.
   - **Found, insufficient balance** → `order.update!(status: :failed, failure_reason: "insufficient_funds")`,
     commit. Cart left intact.
   - **Found, sufficient balance** → deduct the card's balance,
     decrement each product's `stock_quantity`,
     `order.update!(status: :paid, card_last4: card_number.last(4))`,
     clear the cart's items, commit.

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
  out-of-stock.
- **Policy specs**: one per Pundit policy, covering guest/user/admin
  and owner-vs-not-owner combinations.
- **Race-condition spec**: two threads, each on its own DB connection,
  both invoking `CheckoutService` against the same cart concurrently.
  Rails' default transactional-test wrapper prevents real concurrency
  (both threads would share one wrapped transaction), so this spec
  needs `use_transactional_tests = false` (or DatabaseCleaner
  truncation) and will be tagged so it's isolated from the rest of the
  suite.

## Setup changes from the current scaffold

- Swap `sqlite3` → `pg` in `Gemfile` and `config/database.yml` for
  dev/test/prod.
- Add gems: `devise`, `pundit`, `rspec-rails`, `factory_bot_rails`,
  `shoulda-matchers`, `faker` (test/seed data only).
- Remove the default Minitest `test/` directory in favor of `spec/`.
- `db/seeds.rb`: a handful of `PaymentCard`s with clearly fake numbers
  and a mix of balances (including a zero/low-balance one to exercise
  the insufficient-funds path), a few sample `Product`s, one seeded
  admin `User`.
- README: a prominent section stating this payment system is a
  simulation only, not a real payment integration, with pointers to
  the seeded test card numbers.

## Out of scope / explicitly deferred

- Real payment gateway integration of any kind.
- Per-user saved payment methods / wallet.
- Turbo Streams / SPA-style cart updates — classic form + redirect
  flow only.
- Separate inventory audit-log/history model — stock is a plain
  `Product` column.
- Admin management of other users' carts.
