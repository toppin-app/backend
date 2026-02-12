class RemoveInterestCategoriesFromInterests < ActiveRecord::Migration[6.0]
  def up
    # Eliminar foreign key y columna interest_category_id de interests
    remove_foreign_key :interests, :interest_categories if foreign_key_exists?(:interests, :interest_categories)
    remove_column :interests, :interest_category_id if column_exists?(:interests, :interest_category_id)
    
    # Eliminar tabla interest_categories
    drop_table :interest_categories if table_exists?(:interest_categories)
  end

  def down
    # Recrear tabla interest_categories
    create_table :interest_categories do |t|
      t.string :name
      t.timestamps
    end
    
    # Recrear columna y foreign key en interests
    add_reference :interests, :interest_category, null: false, foreign_key: true
  end
end
