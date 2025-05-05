class CreatePurchases < ActiveRecord::Migration[6.0]
  def change
    create_table :purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.string :product_id
      t.text :receipt
      t.boolean :validated, default: false

      t.timestamps
    end
  end
end
