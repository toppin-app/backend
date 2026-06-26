class ReapplyFestivalsVisiblePendingReview < ActiveRecord::Migration[6.0]
  FESTIVAL_CATEGORY = 'festival'.freeze
  REVIEW_STATUS_PENDING = 'pending'.freeze

  class VenueRecord < ActiveRecord::Base
    self.table_name = 'venues'
  end

  # Re-applies the visibility backfill: marks every festival visible while
  # keeping it pending review. Run again whenever new festivals were loaded
  # hidden and need to be revealed.
  def up
    return unless data_source_exists?('venues')

    VenueRecord.reset_column_information

    updates = {}
    updates[:visible] = true if column_exists?(:venues, :visible)
    updates[:review_status] = REVIEW_STATUS_PENDING if column_exists?(:venues, :review_status)
    return if updates.empty?

    updates[:updated_at] = Time.current if column_exists?(:venues, :updated_at)

    VenueRecord.where(category: FESTIVAL_CATEGORY).update_all(updates)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
