class CreateBlackCoffeeGoogleImports < ActiveRecord::Migration[6.0]
  REGIONS = [
    ['Andalucia', 'andalucia'],
    ['Aragon', 'aragon'],
    ['Asturias', 'asturias'],
    ['Islas Baleares', 'islas_baleares'],
    ['Canarias', 'canarias'],
    ['Cantabria', 'cantabria'],
    ['Castilla-La Mancha', 'castilla_la_mancha'],
    ['Castilla y Leon', 'castilla_y_leon'],
    ['Cataluna', 'cataluna'],
    ['Comunidad Valenciana', 'comunidad_valenciana'],
    ['Extremadura', 'extremadura'],
    ['Galicia', 'galicia'],
    ['Comunidad de Madrid', 'comunidad_de_madrid'],
    ['Region de Murcia', 'region_de_murcia'],
    ['Navarra', 'navarra'],
    ['Pais Vasco', 'pais_vasco'],
    ['La Rioja', 'la_rioja'],
    ['Ceuta', 'ceuta'],
    ['Melilla', 'melilla']
  ].freeze

  CATEGORIES = %w[
    restaurante
    hotel
    pub
    cine
    cafeteria
    concierto
    festival
    discoteca
    deportivo
    escape_room
  ].freeze

  def up
    add_google_place_id_to_venues
    add_google_metadata_to_venue_images
    create_import_regions
    create_import_region_categories
    create_import_runs
    create_import_candidates
    seed_regions_and_categories
  end

  def down
    drop_table :black_coffee_import_candidates if table_exists?(:black_coffee_import_candidates)
    drop_table :black_coffee_import_runs if table_exists?(:black_coffee_import_runs)
    drop_table :black_coffee_import_region_categories if table_exists?(:black_coffee_import_region_categories)
    drop_table :black_coffee_import_regions if table_exists?(:black_coffee_import_regions)

    if column_exists?(:venues, :google_place_id)
      remove_index :venues, name: 'idx_venues_google_place_id' if index_exists?(:venues, :google_place_id, name: 'idx_venues_google_place_id')
      remove_column :venues, :google_place_id
    end

    remove_column :venue_images, :author_attributions if column_exists?(:venue_images, :author_attributions)
    remove_column :venue_images, :source if column_exists?(:venue_images, :source)
  end

  private

  def add_google_place_id_to_venues
    add_column :venues, :google_place_id, :string unless column_exists?(:venues, :google_place_id)
    add_index :venues, :google_place_id, unique: true, name: 'idx_venues_google_place_id' unless index_exists?(:venues, :google_place_id, name: 'idx_venues_google_place_id')
  end

  def add_google_metadata_to_venue_images
    add_column :venue_images, :source, :string unless column_exists?(:venue_images, :source)
    add_column :venue_images, :author_attributions, :json unless column_exists?(:venue_images, :author_attributions)
  end

  def create_import_regions
    return if table_exists?(:black_coffee_import_regions)

    create_table :black_coffee_import_regions do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :country_code, null: false, default: 'ES'
      t.string :status, null: false, default: 'pending'
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :black_coffee_import_regions, :slug, unique: true, name: 'idx_bc_import_regions_slug'
  end

  def create_import_region_categories
    return if table_exists?(:black_coffee_import_region_categories)

    create_table :black_coffee_import_region_categories do |t|
      t.references :black_coffee_import_region, null: false, foreign_key: true, index: { name: 'idx_bc_region_categories_region' }
      t.string :category, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :total_candidates, null: false, default: 0
      t.integer :pending_count, null: false, default: 0
      t.integer :approved_count, null: false, default: 0
      t.integer :rejected_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.datetime :last_imported_at

      t.timestamps
    end

    add_index :black_coffee_import_region_categories,
              [:black_coffee_import_region_id, :category],
              unique: true,
              name: 'idx_bc_region_categories_unique'
  end

  def create_import_runs
    return if table_exists?(:black_coffee_import_runs)

    create_table :black_coffee_import_runs do |t|
      t.references :black_coffee_import_region, null: false, foreign_key: true, index: { name: 'idx_bc_import_runs_region' }
      t.references :black_coffee_import_region_category, foreign_key: true, index: { name: 'idx_bc_import_runs_region_category' }
      t.string :category, null: false
      t.string :query
      t.json :google_types
      t.integer :limit, null: false, default: 10
      t.string :status, null: false, default: 'pending'
      t.integer :found_count, null: false, default: 0
      t.integer :candidate_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.integer :approved_count, null: false, default: 0
      t.integer :rejected_count, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :black_coffee_import_runs, :category, name: 'idx_bc_import_runs_category'
    add_index :black_coffee_import_runs, :status, name: 'idx_bc_import_runs_status'
  end

  def create_import_candidates
    return if table_exists?(:black_coffee_import_candidates)

    create_table :black_coffee_import_candidates do |t|
      t.references :black_coffee_import_run, null: false, foreign_key: true, index: { name: 'idx_bc_candidates_run' }
      t.references :black_coffee_import_region, null: false, foreign_key: true, index: { name: 'idx_bc_candidates_region' }
      t.references :black_coffee_import_region_category, foreign_key: true, index: { name: 'idx_bc_candidates_region_category' }
      t.string :status, null: false, default: 'pending'
      t.string :google_place_id
      t.string :name, null: false
      t.string :address
      t.string :city
      t.string :category, null: false
      t.string :subcategory
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.decimal :rating, precision: 3, scale: 2
      t.integer :user_ratings_total
      t.string :website
      t.string :phone
      t.string :google_maps_uri
      t.json :image_urls
      t.json :google_photo_references
      t.json :author_attributions
      t.json :raw_payload
      t.string :duplicate_venue_id
      t.string :approved_venue_id
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :black_coffee_import_candidates, :status, name: 'idx_bc_candidates_status'
    add_index :black_coffee_import_candidates, :google_place_id, name: 'idx_bc_candidates_google_place'
    add_index :black_coffee_import_candidates, :approved_venue_id, name: 'idx_bc_candidates_approved_venue'
    add_index :black_coffee_import_candidates, :duplicate_venue_id, name: 'idx_bc_candidates_duplicate_venue'
  end

  def seed_regions_and_categories
    region_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'black_coffee_import_regions'
    end
    region_category_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'black_coffee_import_region_categories'
    end

    REGIONS.each_with_index do |(name, slug), index|
      region = region_class.find_or_create_by!(slug: slug) do |record|
        record.name = name
        record.country_code = 'ES'
        record.status = 'pending'
        record.position = index
      end

      region.update!(name: name, country_code: 'ES', position: index)

      CATEGORIES.each do |category|
        region_category_class.find_or_create_by!(
          black_coffee_import_region_id: region.id,
          category: category
        )
      end
    end
  end
end
