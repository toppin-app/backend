class AddDescriptionToInfoItemCategories < ActiveRecord::Migration[6.0]
  def change
    add_column :info_item_categories, :description, :string
  end
end
