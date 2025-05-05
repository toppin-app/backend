class CreateUserInfoItemValues < ActiveRecord::Migration[6.0]
  def change
    create_table :user_info_item_values do |t|
      t.references :user, null: false, foreign_key: true
      t.references :info_item_value, null: false, foreign_key: true

      t.timestamps
    end
  end
end
