class RemoveFavoritesCountFromVenues < ActiveRecord::Migration[6.0]
  def up
    remove_index :venues, column: :favorites_count if index_exists?(:venues, :favorites_count)
    remove_column :venues, :favorites_count if column_exists?(:venues, :favorites_count)
  end

  def down
    add_column :venues, :favorites_count, :integer, null: false, default: 0 unless column_exists?(:venues, :favorites_count)
    add_index :venues, :favorites_count unless index_exists?(:venues, :favorites_count)
  end
end
