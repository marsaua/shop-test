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
