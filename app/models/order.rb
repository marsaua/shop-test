class Order < ApplicationRecord
  belongs_to :user
  has_many :order_items, dependent: :destroy

  enum :status, { pending: 0, paid: 1, failed: 2 }, default: :pending

  validates :total_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
