class CreateInfoItemCategories < ActiveRecord::Migration[6.0]
  def change
    create_table :info_item_categories do |t|
      t.string :name

      t.timestamps
    end
  end
end
