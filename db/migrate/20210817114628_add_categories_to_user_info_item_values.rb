class AddCategoriesToUserInfoItemValues < ActiveRecord::Migration[6.0]
  def change
    add_reference :user_info_item_values, :info_item_category, null: false, foreign_key: true
  end
end
