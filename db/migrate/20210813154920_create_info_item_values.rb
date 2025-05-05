class CreateInfoItemValues < ActiveRecord::Migration[6.0]
  def change
    create_table :info_item_values do |t|
      t.string :value
      t.references :info_item_category, null: false, foreign_key: true

      t.timestamps
    end
  end
end
