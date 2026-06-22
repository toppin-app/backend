class EnhanceFanMusicFestImporter < ActiveRecord::Migration[6.0]
  def up
    unless column_exists?(:black_coffee_festival_import_runs, :download_images)
      add_column :black_coffee_festival_import_runs, :download_images, :boolean, null: false, default: true
    end
    unless column_exists?(:black_coffee_festival_import_runs, :only_future)
      add_column :black_coffee_festival_import_runs, :only_future, :boolean, null: false, default: true
    end
    unless column_exists?(:black_coffee_festival_import_runs, :images_downloaded_count)
      add_column :black_coffee_festival_import_runs, :images_downloaded_count, :integer, null: false, default: 0
    end
    unless column_exists?(:black_coffee_festival_import_runs, :past_skipped_count)
      add_column :black_coffee_festival_import_runs, :past_skipped_count, :integer, null: false, default: 0
    end
  end

  def down
    remove_column :black_coffee_festival_import_runs, :past_skipped_count if column_exists?(:black_coffee_festival_import_runs, :past_skipped_count)
    remove_column :black_coffee_festival_import_runs, :images_downloaded_count if column_exists?(:black_coffee_festival_import_runs, :images_downloaded_count)
    remove_column :black_coffee_festival_import_runs, :only_future if column_exists?(:black_coffee_festival_import_runs, :only_future)
    remove_column :black_coffee_festival_import_runs, :download_images if column_exists?(:black_coffee_festival_import_runs, :download_images)
  end
end
