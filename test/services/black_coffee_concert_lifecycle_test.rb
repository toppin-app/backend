require 'test_helper'

class BlackCoffeeConcertLifecycleTest < ActiveSupport::TestCase
  setup do
    skip 'concert lifecycle columns are not available in this test schema' unless required_columns_present?
  end

  test 'marks only concerts before the reference day as occurred and hidden' do
    past_concert = create_concert!(
      name: 'Past Test Concert',
      event_start_at: Time.zone.parse('2026-07-08 21:00'),
      event_end_at: Time.zone.parse('2026-07-08 23:00'),
      festival_start_date: Date.new(2026, 7, 8),
      festival_end_date: Date.new(2026, 7, 8)
    )
    today_concert = create_concert!(
      name: 'Today Test Concert',
      event_start_at: Time.zone.parse('2026-07-09 21:00'),
      event_end_at: Time.zone.parse('2026-07-09 23:00'),
      festival_start_date: Date.new(2026, 7, 9),
      festival_end_date: Date.new(2026, 7, 9)
    )
    future_concert = create_concert!(
      name: 'Future Test Concert',
      event_start_at: Time.zone.parse('2026-07-10 21:00'),
      event_end_at: Time.zone.parse('2026-07-10 23:00'),
      festival_start_date: Date.new(2026, 7, 10),
      festival_end_date: Date.new(2026, 7, 10)
    )
    restaurant = Venue.create!(
      name: 'Not A Concert',
      category: 'restaurante',
      address: 'Calle Test 4',
      city: 'Madrid',
      visible: true,
      featured: true
    )

    result = BlackCoffeeConcertLifecycle.mark_past_concerts_occurred!(reference_date: Date.new(2026, 7, 9))

    assert_equal 1, result.marked_occurred_count
    assert_equal Venue::EVENT_STATUS_OCCURRED, past_concert.reload.event_status
    refute past_concert.visible
    refute past_concert.featured
    assert_equal Venue::EVENT_STATUS_UPCOMING, today_concert.reload.event_status
    assert today_concert.visible
    assert_equal Venue::EVENT_STATUS_UPCOMING, future_concert.reload.event_status
    assert future_concert.visible
    assert restaurant.reload.visible
  end

  private

  def required_columns_present?
    %w[review_status event_status event_start_at event_end_at festival_start_date festival_end_date visible featured].all? do |column|
      Venue.column_names.include?(column)
    end
  end

  def create_concert!(attributes)
    Venue.create!(
      {
        category: 'concierto',
        address: 'Calle Test',
        city: 'Madrid',
        review_status: Venue::REVIEW_STATUS_APPROVED,
        visible: true,
        featured: true,
        event_status: Venue::EVENT_STATUS_UPCOMING
      }.merge(attributes)
    )
  end
end
