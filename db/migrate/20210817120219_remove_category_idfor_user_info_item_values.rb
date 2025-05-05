class RemoveCategoryIdforUserInfoItemValues < ActiveRecord::Migration[6.0]
  def change
	remove_column :user_info_item_values, :info_item_category_id
  end
end
