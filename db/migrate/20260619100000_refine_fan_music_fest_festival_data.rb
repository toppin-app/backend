class RefineFanMusicFestFestivalData < ActiveRecord::Migration[6.0]
  def up
    add_column :venues, :coordinates_source, :string unless column_exists?(:venues, :coordinates_source)
    add_column :venues, :coordinates_confidence, :string unless column_exists?(:venues, :coordinates_confidence)
    add_column :venues, :source_description, :text unless column_exists?(:venues, :source_description)
    add_column :venues, :source_description_language, :string unless column_exists?(:venues, :source_description_language)
    add_column :venues, :source_description_status, :string unless column_exists?(:venues, :source_description_status)
    add_column :venues, :official_url, :text unless column_exists?(:venues, :official_url)
    add_column :venues, :ticket_url, :text unless column_exists?(:venues, :ticket_url)
    add_column :venues, :festival_venue_name, :string unless column_exists?(:venues, :festival_venue_name)
    add_column :venues, :festival_raw_location_text, :text unless column_exists?(:venues, :festival_raw_location_text)

    add_column :black_coffee_festival_import_runs, :operation, :string, null: false, default: 'import' unless column_exists?(:black_coffee_festival_import_runs, :operation)
    add_column :black_coffee_festival_import_runs, :preserve_manual_edits, :boolean, null: false, default: true unless column_exists?(:black_coffee_festival_import_runs, :preserve_manual_edits)

    unless column_exists?(:black_coffee_festival_import_items, :latitude)
      add_column :black_coffee_festival_import_items, :latitude, :decimal, precision: 10, scale: 6
    end
    unless column_exists?(:black_coffee_festival_import_items, :longitude)
      add_column :black_coffee_festival_import_items, :longitude, :decimal, precision: 10, scale: 6
    end
    add_column :black_coffee_festival_import_items, :coordinates_source, :string unless column_exists?(:black_coffee_festival_import_items, :coordinates_source)
    add_column :black_coffee_festival_import_items, :coordinates_confidence, :string unless column_exists?(:black_coffee_festival_import_items, :coordinates_confidence)
    add_column :black_coffee_festival_import_items, :source_description, :text unless column_exists?(:black_coffee_festival_import_items, :source_description)
    add_column :black_coffee_festival_import_items, :source_description_language, :string unless column_exists?(:black_coffee_festival_import_items, :source_description_language)
    add_column :black_coffee_festival_import_items, :source_description_status, :string unless column_exists?(:black_coffee_festival_import_items, :source_description_status)
    add_column :black_coffee_festival_import_items, :official_url, :text unless column_exists?(:black_coffee_festival_import_items, :official_url)
    add_column :black_coffee_festival_import_items, :ticket_url, :text unless column_exists?(:black_coffee_festival_import_items, :ticket_url)
    add_column :black_coffee_festival_import_items, :festival_venue_name, :string unless column_exists?(:black_coffee_festival_import_items, :festival_venue_name)
    add_column :black_coffee_festival_import_items, :warning_message, :text unless column_exists?(:black_coffee_festival_import_items, :warning_message)

    add_index :venues, :source_description_status, name: 'idx_venues_source_description_status' unless index_exists?(:venues, :source_description_status, name: 'idx_venues_source_description_status')
    add_index :black_coffee_festival_import_runs, :operation, name: 'idx_bc_festival_runs_operation' unless index_exists?(:black_coffee_festival_import_runs, :operation, name: 'idx_bc_festival_runs_operation')
  end

  def down
    remove_index :black_coffee_festival_import_runs, name: 'idx_bc_festival_runs_operation' if index_exists?(:black_coffee_festival_import_runs, :operation, name: 'idx_bc_festival_runs_operation')
    remove_index :venues, name: 'idx_venues_source_description_status' if index_exists?(:venues, :source_description_status, name: 'idx_venues_source_description_status')

    remove_column :black_coffee_festival_import_items, :warning_message if column_exists?(:black_coffee_festival_import_items, :warning_message)
    remove_column :black_coffee_festival_import_items, :festival_venue_name if column_exists?(:black_coffee_festival_import_items, :festival_venue_name)
    remove_column :black_coffee_festival_import_items, :ticket_url if column_exists?(:black_coffee_festival_import_items, :ticket_url)
    remove_column :black_coffee_festival_import_items, :official_url if column_exists?(:black_coffee_festival_import_items, :official_url)
    remove_column :black_coffee_festival_import_items, :source_description_status if column_exists?(:black_coffee_festival_import_items, :source_description_status)
    remove_column :black_coffee_festival_import_items, :source_description_language if column_exists?(:black_coffee_festival_import_items, :source_description_language)
    remove_column :black_coffee_festival_import_items, :source_description if column_exists?(:black_coffee_festival_import_items, :source_description)
    remove_column :black_coffee_festival_import_items, :coordinates_confidence if column_exists?(:black_coffee_festival_import_items, :coordinates_confidence)
    remove_column :black_coffee_festival_import_items, :coordinates_source if column_exists?(:black_coffee_festival_import_items, :coordinates_source)
    remove_column :black_coffee_festival_import_items, :longitude if column_exists?(:black_coffee_festival_import_items, :longitude)
    remove_column :black_coffee_festival_import_items, :latitude if column_exists?(:black_coffee_festival_import_items, :latitude)

    remove_column :black_coffee_festival_import_runs, :preserve_manual_edits if column_exists?(:black_coffee_festival_import_runs, :preserve_manual_edits)
    remove_column :black_coffee_festival_import_runs, :operation if column_exists?(:black_coffee_festival_import_runs, :operation)

    remove_column :venues, :festival_raw_location_text if column_exists?(:venues, :festival_raw_location_text)
    remove_column :venues, :festival_venue_name if column_exists?(:venues, :festival_venue_name)
    remove_column :venues, :ticket_url if column_exists?(:venues, :ticket_url)
    remove_column :venues, :official_url if column_exists?(:venues, :official_url)
    remove_column :venues, :source_description_status if column_exists?(:venues, :source_description_status)
    remove_column :venues, :source_description_language if column_exists?(:venues, :source_description_language)
    remove_column :venues, :source_description if column_exists?(:venues, :source_description)
    remove_column :venues, :coordinates_confidence if column_exists?(:venues, :coordinates_confidence)
    remove_column :venues, :coordinates_source if column_exists?(:venues, :coordinates_source)
  end
end
