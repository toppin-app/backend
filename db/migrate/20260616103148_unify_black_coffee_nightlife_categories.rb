require 'digest'

class UnifyBlackCoffeeNightlifeCategories < ActiveRecord::Migration[6.0]
  OLD_CATEGORIES = %w[pub discoteca].freeze
  NEW_CATEGORY = 'nightlife'.freeze
  MUSEUMS_CATEGORY = 'museums_galleries'.freeze
  MUSEUMS_SUBCATEGORIES = %w[museo galeria_arte centro_cultural].freeze
  CATEGORY_COLUMNS = {
    'venues' => %w[category],
    'black_coffee_import_candidates' => %w[category],
    'black_coffee_import_runs' => %w[category],
    'black_coffee_bulk_import_steps' => %w[category],
    'black_coffee_bulk_imports' => %w[current_category],
    'black_coffee_review_batch_items' => %w[category_correction_from category_correction_to]
  }.freeze
  JSON_CATEGORY_COLUMNS = {
    'black_coffee_bulk_imports' => %w[categories_payload],
    'black_coffee_review_batches' => %w[filters_payload]
  }.freeze

  class VenueRecord < ActiveRecord::Base
    self.table_name = 'venues'
  end

  class VenueSubcategoryRecord < ActiveRecord::Base
    self.table_name = 'venue_subcategories'
    self.primary_key = 'id'
  end

  class ImportRegionCategoryRecord < ActiveRecord::Base
    self.table_name = 'black_coffee_import_region_categories'
  end

  class ImportRunRecord < ActiveRecord::Base
    self.table_name = 'black_coffee_import_runs'
  end

  class ImportCandidateRecord < ActiveRecord::Base
    self.table_name = 'black_coffee_import_candidates'
  end

  class GoogleImportFilterRecord < ActiveRecord::Base
    self.table_name = 'black_coffee_google_import_filters'
  end

  def up
    reset_model_information!
    create_fixed_subcategories!
    remap_venue_subcategories!
    update_simple_category_columns!
    merge_region_categories!
    merge_google_import_filters!
    normalize_json_category_columns!
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def reset_model_information!
    [
      VenueRecord,
      VenueSubcategoryRecord,
      ImportRegionCategoryRecord,
      ImportRunRecord,
      ImportCandidateRecord,
      GoogleImportFilterRecord
    ].each do |model|
      model.reset_column_information if data_source_exists?(model.table_name)
    end
  end

  def create_fixed_subcategories!
    return unless data_source_exists?('venue_subcategories')

    now = Time.current
    { MUSEUMS_CATEGORY => MUSEUMS_SUBCATEGORIES }.each do |category, names|
      names.each do |name|
        next if VenueSubcategoryRecord.where(category: category, name: name).exists?

        VenueSubcategoryRecord.create!(
          id: subcategory_id_for(category, name),
          category: category,
          name: name,
          created_at: now,
          updated_at: now
        )
      end
    end
  end

  def remap_venue_subcategories!
    return unless data_source_exists?('venue_subcategories')
    return unless data_source_exists?('venues') && column_exists?(:venues, :venue_subcategory_id)

    VenueSubcategoryRecord.where(category: OLD_CATEGORIES).find_each do |subcategory|
      VenueRecord.where(venue_subcategory_id: subcategory.id).update_all(venue_subcategory_id: nil)
    end

    VenueSubcategoryRecord.where(category: OLD_CATEGORIES).delete_all
  end

  def update_simple_category_columns!
    CATEGORY_COLUMNS.each do |table_name, columns|
      next unless data_source_exists?(table_name)

      columns.each do |column_name|
        next unless column_exists?(table_name, column_name)

        quoted_table = quote_table_name(table_name)
        quoted_column = quote_column_name(column_name)
        execute <<~SQL.squish
          UPDATE #{quoted_table}
          SET #{quoted_column} = #{quote(NEW_CATEGORY)}
          WHERE #{quoted_column} IN (#{OLD_CATEGORIES.map { |category| quote(category) }.join(', ')})
        SQL
      end
    end
  end

  def merge_region_categories!
    return unless data_source_exists?('black_coffee_import_region_categories')

    ImportRegionCategoryRecord.where(category: OLD_CATEGORIES).pluck(:black_coffee_import_region_id).uniq.each do |region_id|
      legacy_rows = ImportRegionCategoryRecord.where(black_coffee_import_region_id: region_id, category: OLD_CATEGORIES).order(:id).to_a
      next if legacy_rows.empty?

      target = ImportRegionCategoryRecord.find_by(black_coffee_import_region_id: region_id, category: NEW_CATEGORY) || legacy_rows.shift
      target.update_columns(category: NEW_CATEGORY, updated_at: Time.current) if target.category != NEW_CATEGORY

      legacy_rows.each do |row|
        reassign_region_category_references!(from_id: row.id, to_id: target.id)
        row.destroy!
      end

      refresh_region_category_counts!(target)
    end
  end

  def merge_google_import_filters!
    return unless data_source_exists?('black_coffee_google_import_filters')

    legacy_filters = GoogleImportFilterRecord.where(category: OLD_CATEGORIES).order(:id).to_a
    return if legacy_filters.empty?

    target = GoogleImportFilterRecord.find_by(category: NEW_CATEGORY) || legacy_filters.shift
    target.update_columns(category: NEW_CATEGORY, updated_at: Time.current) if target.category != NEW_CATEGORY

    legacy_filters.each do |filter|
      merge_json_array_column!(target, filter, 'excluded_primary_types')
      merge_json_array_column!(target, filter, 'excluded_types')
      merge_json_array_column!(target, filter, 'excluded_keywords')
      filter.destroy!
    end
  end

  def normalize_json_category_columns!
    JSON_CATEGORY_COLUMNS.each do |table_name, columns|
      next unless data_source_exists?(table_name)

      record_class = Class.new(ActiveRecord::Base) do
        self.table_name = table_name
      end
      record_class.reset_column_information

      columns.each do |column_name|
        next unless column_exists?(table_name, column_name)

        record_class.where.not(column_name => nil).find_each do |record|
          payload = record.public_send(column_name)
          normalized_payload = normalize_payload(payload)
          next if normalized_payload == payload

          record.update_columns(column_name => normalized_payload, updated_at: Time.current)
        end
      end
    end
  end

  def reassign_region_category_references!(from_id:, to_id:)
    if data_source_exists?('black_coffee_import_runs') && column_exists?(:black_coffee_import_runs, :black_coffee_import_region_category_id)
      ImportRunRecord.where(black_coffee_import_region_category_id: from_id).update_all(
        black_coffee_import_region_category_id: to_id,
        updated_at: Time.current
      )
    end

    if data_source_exists?('black_coffee_import_candidates') && column_exists?(:black_coffee_import_candidates, :black_coffee_import_region_category_id)
      ImportCandidateRecord.where(black_coffee_import_region_category_id: from_id).update_all(
        black_coffee_import_region_category_id: to_id,
        updated_at: Time.current
      )
    end
  end

  def refresh_region_category_counts!(region_category)
    return unless data_source_exists?('black_coffee_import_candidates')
    return unless column_exists?(:black_coffee_import_candidates, :black_coffee_import_region_category_id)

    counts = ImportCandidateRecord.where(black_coffee_import_region_category_id: region_category.id).group(:status).count
    attributes = {
      total_candidates: counts.values.sum,
      pending_count: counts['pending'].to_i,
      approved_count: counts['approved'].to_i,
      rejected_count: counts['rejected'].to_i,
      duplicate_count: counts['duplicate'].to_i,
      updated_at: Time.current
    }
    region_category.update_columns(attributes.slice(*region_category.attribute_names.map(&:to_sym)))
  end

  def merge_json_array_column!(target, source, column_name)
    return unless target.has_attribute?(column_name) && source.has_attribute?(column_name)

    merged = (array_payload(target.public_send(column_name)) + array_payload(source.public_send(column_name))).uniq
    target.update_columns(column_name => merged, updated_at: Time.current)
  end

  def normalize_payload(payload)
    case payload
    when Array
      payload.map { |value| normalize_payload(value) }.uniq
    when Hash
      payload.transform_values { |value| normalize_payload(value) }
    when String
      begin
        parsed_payload = JSON.parse(payload)
        return normalize_payload(parsed_payload)
      rescue JSON::ParserError
        OLD_CATEGORIES.include?(payload) ? NEW_CATEGORY : payload
      end
    else
      payload
    end
  end

  def array_payload(value)
    case value
    when Array
      value
    when String
      JSON.parse(value)
    else
      []
    end
  rescue JSON::ParserError
    []
  end

  def subcategory_id_for(category, name)
    "sub_#{Digest::SHA256.hexdigest("#{category}:#{name}")[0, 12]}"
  end
end
