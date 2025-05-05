class AddCategoryNameToUserInfoItemValues < ActiveRecord::Migration[6.0]
  def change
    add_column :user_info_item_values, :category_name, :string
  end
end
