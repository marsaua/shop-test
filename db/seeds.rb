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
