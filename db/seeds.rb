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
puts "Seeded #{products.size} legacy products."

# Electronics demo catalog. Prices are in UAH (price_cents is kopiykas).
# Brands/models are fictional. Keyed by SKU so this is safe to rerun.
electronics = [
  # Smartphones
  { sku: "SP-001", name: "Voltrix Nova 12", brand: "Voltrix", model: "Nova 12", category: :smartphones,
    description: "A well-rounded everyday smartphone with a bright display and all-day battery life.",
    price_cents: 2_499_900, previous_price_cents: nil, stock_quantity: 25, color: "Midnight Black",
    warranty_months: 24, weight_grams: 189,
    specifications: { storage_gb: 128, ram_gb: 8, screen_inches: 6.1, chipset: "Voltrix X2", battery_mah: 3800, os: "AuroraOS 5" } },
  { sku: "SP-002", name: "Voltrix Nova 12 Pro", brand: "Voltrix", model: "Nova 12 Pro", category: :smartphones,
    description: "The Pro variant of the Nova 12 with more storage, more RAM, and a larger screen.",
    price_cents: 3_499_900, previous_price_cents: 3_999_900, stock_quantity: 12, color: "Titanium Silver",
    warranty_months: 24, weight_grams: 205,
    specifications: { storage_gb: 256, ram_gb: 12, screen_inches: 6.7, chipset: "Voltrix X2 Pro", battery_mah: 4500, os: "AuroraOS 5" } },
  { sku: "SP-003", name: "Nordheim Pulse S", brand: "Nordheim", model: "Pulse S", category: :smartphones,
    description: "A fast mid-range smartphone with a large battery for heavy daily use.",
    price_cents: 1_599_900, previous_price_cents: nil, stock_quantity: 40, color: "Ocean Blue",
    warranty_months: 12, weight_grams: 172,
    specifications: { storage_gb: 128, ram_gb: 6, screen_inches: 6.4, chipset: "Nordheim N7", battery_mah: 4200, os: "DroidNext 14" } },
  { sku: "SP-004", name: "Kaigen Zeta 5", brand: "Kaigen", model: "Zeta 5", category: :smartphones,
    description: "An affordable entry-level smartphone, currently on sale.",
    price_cents: 1_249_900, previous_price_cents: 1_499_900, stock_quantity: 3, color: "Forest Green",
    warranty_months: 12, weight_grams: 180,
    specifications: { storage_gb: 64, ram_gb: 4, screen_inches: 6.2, chipset: "Kaigen K5", battery_mah: 4000, os: "DroidNext 14" } },
  { sku: "SP-005", name: "Solace Aeon Mini", brand: "Solace", model: "Aeon Mini", category: :smartphones,
    description: "A compact, budget-friendly smartphone for light everyday use.",
    price_cents: 999_900, previous_price_cents: nil, stock_quantity: 0, color: "Coral",
    warranty_months: 12, weight_grams: 158,
    specifications: { storage_gb: 64, ram_gb: 4, screen_inches: 5.8, chipset: "Solace S1", battery_mah: 3200, os: "DroidNext 13" } },

  # Laptops
  { sku: "LT-001", name: "Nordheim Book Air 14", brand: "Nordheim", model: "Book Air 14", category: :laptops,
    description: "A lightweight everyday laptop built for portability.",
    price_cents: 3_299_900, previous_price_cents: nil, stock_quantity: 15, color: "Silver",
    warranty_months: 24, weight_grams: 1290,
    specifications: { processor: "Nordheim N7 Ultra", ram_gb: 16, storage_gb: 512, graphics: "Integrated N-Graphics", screen_inches: 14, os: "AuroraOS Desktop" } },
  { sku: "LT-002", name: "Nordheim Book Pro 16", brand: "Nordheim", model: "Book Pro 16", category: :laptops,
    description: "A high-performance laptop for professionals, on sale for a limited time.",
    price_cents: 5_499_900, previous_price_cents: 5_999_900, stock_quantity: 8, color: "Space Gray",
    warranty_months: 24, weight_grams: 2100,
    specifications: { processor: "Nordheim N9 Max", ram_gb: 32, storage_gb: 1024, graphics: "N-Graphics Pro 16-core", screen_inches: 16, os: "AuroraOS Desktop" } },
  { sku: "LT-003", name: "Kaigen Forge 15", brand: "Kaigen", model: "Forge 15", category: :laptops,
    description: "A dependable all-purpose laptop for work and study.",
    price_cents: 2_799_900, previous_price_cents: nil, stock_quantity: 20, color: "Black",
    warranty_months: 12, weight_grams: 1850,
    specifications: { processor: "Kaigen Ryder 7", ram_gb: 16, storage_gb: 512, graphics: "Vega Onboard", screen_inches: 15.6, os: "Windows Prime 12" } },
  { sku: "LT-004", name: "Pulsewave Edge Gaming 17", brand: "Pulsewave", model: "Edge Gaming 17", category: :laptops,
    description: "A high-refresh gaming laptop with discrete graphics.",
    price_cents: 4_799_900, previous_price_cents: 5_299_900, stock_quantity: 2, color: "Gunmetal",
    warranty_months: 24, weight_grams: 2600,
    specifications: { processor: "Kaigen Ryder 9", ram_gb: 32, storage_gb: 1024, graphics: "Pulsewave RTX-70", screen_inches: 17.3, os: "Windows Prime 12" } },
  { sku: "LT-005", name: "Solace Slim Chrome 13", brand: "Solace", model: "Slim Chrome 13", category: :laptops,
    description: "A simple, affordable laptop for browsing and everyday tasks.",
    price_cents: 1_699_900, previous_price_cents: nil, stock_quantity: 0, color: "White",
    warranty_months: 12, weight_grams: 1180,
    specifications: { processor: "Solace SC-3", ram_gb: 8, storage_gb: 256, graphics: "Integrated", screen_inches: 13.3, os: "ChromeLite OS" } },

  # TVs and monitors
  { sku: "TV-001", name: "Brightline Vista 55 4K", brand: "Brightline", model: "Vista 55", category: :tvs_and_monitors,
    description: "A 55-inch 4K smart TV for the living room.",
    price_cents: 2_199_900, previous_price_cents: nil, stock_quantity: 18, color: "Black",
    warranty_months: 24, weight_grams: 12_500,
    specifications: { screen_inches: 55, resolution: "3840x2160", panel_type: "VA", refresh_rate_hz: 60, ports: [ "HDMI x3", "USB x2", "Optical Audio" ] } },
  { sku: "TV-002", name: "Brightline Vista 65 4K", brand: "Brightline", model: "Vista 65", category: :tvs_and_monitors,
    description: "A larger 65-inch 4K smart TV, currently discounted.",
    price_cents: 3_499_900, previous_price_cents: 3_999_900, stock_quantity: 6, color: "Black",
    warranty_months: 24, weight_grams: 18_700,
    specifications: { screen_inches: 65, resolution: "3840x2160", panel_type: "VA", refresh_rate_hz: 60, ports: [ "HDMI x4", "USB x2", "Optical Audio", "LAN" ] } },
  { sku: "TV-003", name: "Arcstream ProView 27 QHD", brand: "Arcstream", model: "ProView 27", category: :tvs_and_monitors,
    description: "A 27-inch QHD monitor with a high refresh rate for gaming and productivity.",
    price_cents: 1_299_900, previous_price_cents: nil, stock_quantity: 30, color: "Black",
    warranty_months: 36, weight_grams: 4300,
    specifications: { screen_inches: 27, resolution: "2560x1440", panel_type: "IPS", refresh_rate_hz: 144, ports: [ "HDMI x2", "DisplayPort x1", "USB-C" ] } },
  { sku: "TV-004", name: "Arcstream ProView 32 4K", brand: "Arcstream", model: "ProView 32", category: :tvs_and_monitors,
    description: "A larger 32-inch 4K monitor for detail-focused work.",
    price_cents: 1_899_900, previous_price_cents: 2_199_900, stock_quantity: 1, color: "White",
    warranty_months: 36, weight_grams: 6100,
    specifications: { screen_inches: 32, resolution: "3840x2160", panel_type: "IPS", refresh_rate_hz: 60, ports: [ "HDMI x2", "DisplayPort x1" ] } },
  { sku: "TV-005", name: "Ferro FastSync 24 FHD", brand: "Ferro", model: "FastSync 24", category: :tvs_and_monitors,
    description: "A budget 24-inch FHD monitor with a fast refresh rate.",
    price_cents: 699_900, previous_price_cents: nil, stock_quantity: 0, color: "Black",
    warranty_months: 24, weight_grams: 3200,
    specifications: { screen_inches: 24, resolution: "1920x1080", panel_type: "TN", refresh_rate_hz: 165, ports: [ "HDMI x1", "DisplayPort x1" ] } },

  # Headphones
  { sku: "HP-001", name: "Halcyon Aero ANC", brand: "Halcyon", model: "Aero ANC", category: :headphones,
    description: "Over-ear wireless headphones with active noise cancellation, on sale.",
    price_cents: 899_900, previous_price_cents: 1_099_900, stock_quantity: 22, color: "Black",
    warranty_months: 12, weight_grams: 254,
    specifications: { connection_type: "Bluetooth 5.3", form_factor: "Over-ear", active_noise_cancellation: true, battery_life_hours: 30 } },
  { sku: "HP-002", name: "Halcyon Aero Lite", brand: "Halcyon", model: "Aero Lite", category: :headphones,
    description: "A lighter, more affordable over-ear wireless headphone.",
    price_cents: 499_900, previous_price_cents: nil, stock_quantity: 35, color: "White",
    warranty_months: 12, weight_grams: 210,
    specifications: { connection_type: "Bluetooth 5.2", form_factor: "On-ear", active_noise_cancellation: false, battery_life_hours: 20 } },
  { sku: "HP-003", name: "Pulsewave Buds Pro", brand: "Pulsewave", model: "Buds Pro", category: :headphones,
    description: "True wireless earbuds with active noise cancellation.",
    price_cents: 599_900, previous_price_cents: 699_900, stock_quantity: 4, color: "Black",
    warranty_months: 12, weight_grams: 52,
    specifications: { connection_type: "Bluetooth 5.3", form_factor: "In-ear (TWS)", active_noise_cancellation: true, battery_life_hours: 8 } },
  { sku: "HP-004", name: "Quanta StudioMon", brand: "Quanta", model: "StudioMon", category: :headphones,
    description: "Wired over-ear studio monitor headphones for accurate sound.",
    price_cents: 349_900, previous_price_cents: nil, stock_quantity: 15, color: "Silver",
    warranty_months: 24, weight_grams: 290,
    specifications: { connection_type: "Wired 3.5mm", form_factor: "Over-ear", active_noise_cancellation: false, battery_life_hours: 0 } },
  { sku: "HP-005", name: "Quanta SportBuds", brand: "Quanta", model: "SportBuds", category: :headphones,
    description: "Compact wireless earbuds built for workouts.",
    price_cents: 249_900, previous_price_cents: nil, stock_quantity: 0, color: "Coral",
    warranty_months: 6, weight_grams: 48,
    specifications: { connection_type: "Bluetooth 5.1", form_factor: "In-ear (TWS)", active_noise_cancellation: false, battery_life_hours: 6 } },

  # Accessories
  { sku: "AC-001", name: "Ferro FastCharge 65W GaN", brand: "Ferro", model: "FastCharge 65W", category: :accessories,
    description: "A compact 65W GaN charger for laptops, phones, and tablets.",
    price_cents: 99_900, previous_price_cents: nil, stock_quantity: 60, color: "White",
    warranty_months: 12, weight_grams: 110,
    specifications: { connector_type: "USB-C", power_output_w: 65, compatibility: "Laptops, phones, tablets" } },
  { sku: "AC-002", name: "Ferro Braided USB-C Cable 2m", brand: "Ferro", model: "Braided USB-C 2m", category: :accessories,
    description: "A durable braided USB-C to USB-C charging cable.",
    price_cents: 34_900, previous_price_cents: nil, stock_quantity: 100, color: "Black",
    warranty_months: 6, weight_grams: 60,
    specifications: { connector_type: "USB-C to USB-C", power_output_w: 60, compatibility: "Universal USB-C devices", cable_length_m: 2 } },
  { sku: "AC-003", name: "Arcstream Wireless Charge Pad", brand: "Arcstream", model: "Charge Pad", category: :accessories,
    description: "A Qi wireless charging pad for compatible phones, on sale.",
    price_cents: 79_900, previous_price_cents: 99_900, stock_quantity: 40, color: "Black",
    warranty_months: 12, weight_grams: 145,
    specifications: { connector_type: "Qi wireless", power_output_w: 15, compatibility: "Qi-enabled phones" } },
  { sku: "AC-004", name: "Quanta Travel Power Bank 20000mAh", brand: "Quanta", model: "Power Bank 20000", category: :accessories,
    description: "A high-capacity power bank for charging devices on the go.",
    price_cents: 149_900, previous_price_cents: 179_900, stock_quantity: 2, color: "Gray",
    warranty_months: 12, weight_grams: 420,
    specifications: { connector_type: "USB-A / USB-C", power_output_w: 22, compatibility: "Phones, tablets, small electronics" } },
  { sku: "AC-005", name: "Kaigen Laptop Sleeve 15\"", brand: "Kaigen", model: "Sleeve 15", category: :accessories,
    description: "A padded protective sleeve for laptops up to 15.6 inches.",
    price_cents: 59_900, previous_price_cents: nil, stock_quantity: 0, color: "Navy",
    warranty_months: nil, weight_grams: 220,
    specifications: { compatibility: "Laptops up to 15.6\"" } }
]

electronics.each do |attrs|
  Product.find_or_create_by!(sku: attrs[:sku]) do |product|
    product.assign_attributes(attrs.except(:sku))
  end
end
puts "Seeded #{electronics.size} electronics products (#{Product.count} products total)."
