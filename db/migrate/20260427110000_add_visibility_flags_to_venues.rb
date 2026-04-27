class AddVisibilityFlagsToVenues < ActiveRecord::Migration[6.0]
  def up
    add_column :venues, :internal_test, :boolean, null: false, default: false unless column_exists?(:venues, :internal_test)
    add_column :venues, :payment_current, :boolean, null: false, default: true unless column_exists?(:venues, :payment_current)
    add_column :venues, :visible, :boolean, null: false, default: true unless column_exists?(:venues, :visible)

    add_index :venues, :visible, name: 'idx_venues_visible' unless index_exists?(:venues, :visible, name: 'idx_venues_visible')

    venue_record = Class.new(ActiveRecord::Base) do
      self.table_name = 'venues'
    end
    venue_record.reset_column_information
    venue_record.update_all(internal_test: true, payment_current: true, visible: true)
  end

  def down
    remove_index :venues, name: 'idx_venues_visible' if index_exists?(:venues, :visible, name: 'idx_venues_visible')
    remove_column :venues, :visible if column_exists?(:venues, :visible)
    remove_column :venues, :payment_current if column_exists?(:venues, :payment_current)
    remove_column :venues, :internal_test if column_exists?(:venues, :internal_test)
  end
end
