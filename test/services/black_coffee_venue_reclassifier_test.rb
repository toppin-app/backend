require 'test_helper'
require 'minitest/mock'
require 'ostruct'

class BlackCoffeeVenueReclassifierTest < ActiveSupport::TestCase
  FakeUpdateScope = Struct.new(:updates) do
    def update_all(attributes)
      updates << attributes
      updates.size
    end
  end

  test 'normalizes filters and refuses all filtered selection without any filter' do
    reclassifier = BlackCoffeeVenueReclassifier.new(
      name_query: '  ',
      categories: ['not_a_category'],
      city: nil,
      google_tag: ' '
    )

    refute reclassifier.filters_present?
    assert_equal [], reclassifier.categories

    error = assert_raises(ArgumentError) do
      reclassifier.reclassify!(
        target_category: 'restaurante',
        selection_mode: BlackCoffeeVenueReclassifier::SELECTION_FILTERED,
        selected_ids: [],
        confirmation_text: BlackCoffeeVenueReclassifier::CONFIRMATION_TEXT
      )
    end

    assert_equal 'Aplica al menos un filtro antes de reclasificar todos los resultados.', error.message
  end

  test 'selected reclassification updates changed venues and logs audit payload' do
    reclassifier = BlackCoffeeVenueReclassifier.new(name_query: 'bar', categories: ['cafeteria'])
    reclassifier.define_singleton_method(:venue_ids_for_selection) do |selection_mode, selected_ids|
      assert_equal BlackCoffeeVenueReclassifier::SELECTION_SELECTED, selection_mode
      assert_equal %w[ven_1 ven_2 ven_3], selected_ids
      %w[ven_1 ven_2 ven_3]
    end
    reclassifier.define_singleton_method(:has_venue_column?) do |column_name|
      %w[venue_subcategory_id reviewed_at reviewed_by_id].include?(column_name.to_s)
    end

    fixed_time = Time.zone.parse('2026-06-10 12:30:00')
    reviewer = OpenStruct.new(id: 42)
    updates = []
    where_calls = []
    logger = Minitest::Mock.new
    logger.expect(:info, nil) do |payload|
      parsed = JSON.parse(payload)
      parsed['action'] == 'bulk_reclassify_black_coffee_places' &&
        parsed['affectedPlaceIds'] == %w[ven_1 ven_3] &&
        parsed['newCategory'] == 'restaurante' &&
        parsed['changedBy'] == 42
    end

    where = lambda do |filters|
      where_calls << filters

      if where_calls.size == 1
        Struct.new(:rows) do
          def pluck(*columns)
            raise "Unexpected columns: #{columns.inspect}" unless columns == [:id, :category]

            rows
          end
        end.new([
          ['ven_1', 'cafeteria'],
          ['ven_2', 'restaurante'],
          ['ven_3', 'pub']
        ])
      else
        FakeUpdateScope.new(updates)
      end
    end

    transaction = ->(&block) { block.call }

    ActiveRecord::Base.stub(:transaction, transaction) do
      Time.stub(:current, fixed_time) do
        Venue.stub(:where, where) do
          result = reclassifier.reclassify!(
            target_category: 'restaurante',
            selection_mode: BlackCoffeeVenueReclassifier::SELECTION_SELECTED,
            selected_ids: %w[ven_1 ven_2 ven_3],
            confirmation_text: BlackCoffeeVenueReclassifier::CONFIRMATION_TEXT,
            changed_by: reviewer,
            logger: logger
          )

          assert_equal 3, result[:selected_count]
          assert_equal 2, result[:changed_count]
          assert_equal 1, result[:unchanged_count]
          assert_equal %w[ven_1 ven_3], result[:affected_place_ids]
        end
      end
    end

    logger.verify
    assert_equal [{ id: %w[ven_1 ven_2 ven_3] }, { id: %w[ven_1 ven_3] }], where_calls
    assert_equal(
      {
        category: 'restaurante',
        updated_at: fixed_time,
        venue_subcategory_id: nil,
        reviewed_at: fixed_time,
        reviewed_by_id: 42
      },
      updates.first
    )
  end

  test 'requires valid target category and exact confirmation text' do
    reclassifier = BlackCoffeeVenueReclassifier.new(name_query: 'bar')

    invalid_category_error = assert_raises(ArgumentError) do
      reclassifier.reclassify!(
        target_category: 'nope',
        selection_mode: BlackCoffeeVenueReclassifier::SELECTION_SELECTED,
        selected_ids: ['ven_1'],
        confirmation_text: BlackCoffeeVenueReclassifier::CONFIRMATION_TEXT
      )
    end
    assert_equal 'Debes elegir una categoria destino valida.', invalid_category_error.message

    confirmation_error = assert_raises(ArgumentError) do
      reclassifier.reclassify!(
        target_category: 'restaurante',
        selection_mode: BlackCoffeeVenueReclassifier::SELECTION_SELECTED,
        selected_ids: ['ven_1'],
        confirmation_text: 'reclasificar'
      )
    end
    assert_equal 'Escribe RECLASIFICAR para confirmar esta reclasificacion masiva.', confirmation_error.message
  end
end
