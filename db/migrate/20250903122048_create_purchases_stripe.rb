class CreatePurchasesStripe < ActiveRecord::Migration[6.0]
  def change
    create_table :purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.string :payment_id, null: false
      t.string :status, null: false, default: "pending"
      t.string :product_key, null: false
      t.integer :prize
      t.datetime :started_at
      t.integer :increment
      t.timestamps
    end
  end
end