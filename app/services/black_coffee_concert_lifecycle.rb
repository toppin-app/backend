class BlackCoffeeConcertLifecycle
  Result = Struct.new(:marked_occurred_count, :reference_date, keyword_init: true)

  def self.mark_past_concerts_occurred!(reference_date: Time.zone.today)
    new(reference_date: reference_date).mark_past_concerts_occurred!
  end

  def initialize(reference_date: Time.zone.today)
    @reference_date = reference_date.to_date
  end

  def mark_past_concerts_occurred!
    return Result.new(marked_occurred_count: 0, reference_date: reference_date) unless Venue.column_names.include?('event_status')

    affected = past_concert_scope.update_all(update_attributes)

    Result.new(marked_occurred_count: affected, reference_date: reference_date)
  end

  private

  attr_reader :reference_date

  def update_attributes
    attrs = {
      event_status: Venue::EVENT_STATUS_OCCURRED,
      featured: false,
      updated_at: Time.current
    }
    attrs[:visible] = false if Venue.column_names.include?('visible')
    attrs
  end

  def past_concert_scope
    scope = Venue.where(category: 'concierto')
                 .where.not(event_status: Venue::EVENT_STATUS_OCCURRED)

    if Venue.column_names.include?('event_start_at') && Venue.column_names.include?('festival_start_date')
      scope.where('DATE(COALESCE(event_end_at, event_start_at, festival_end_date, festival_start_date)) < ?', reference_date)
    elsif Venue.column_names.include?('festival_start_date')
      scope.where('COALESCE(festival_end_date, festival_start_date) < ?', reference_date)
    else
      scope.none
    end
  end
end
