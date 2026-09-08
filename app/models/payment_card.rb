# Fake wallet for the simulated payment system. These are NOT real
# payment cards — no real bank or card network is ever contacted.
# See docs/superpowers/specs/2026-09-08-online-store-design.md.
class PaymentCard < ApplicationRecord
  validates :card_number, presence: true, uniqueness: true
  validates :balance_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
