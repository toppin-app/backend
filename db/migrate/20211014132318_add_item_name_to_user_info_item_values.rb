class AddItemNameToUserInfoItemValues < ActiveRecord::Migration[6.0]
  def change
    add_column :user_info_item_values, :item_name, :string
  end
end
