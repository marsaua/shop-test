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
