class AddReviewWorkflowToBlackCoffeeVenues < ActiveRecord::Migration[6.0]
  def up
    add_venue_review_columns
    create_review_batches
    create_review_batch_items
  end

  def down
    drop_table :black_coffee_review_batch_items, if_exists: true
    drop_table :black_coffee_review_batches, if_exists: true

    if table_exists?(:venues)
      if foreign_key_exists?(:venues, :users, column: :reviewed_by_id)
        remove_foreign_key :venues, column: :reviewed_by_id
      end
      remove_index :venues, name: 'idx_venues_review_status' if index_exists?(:venues, :review_status, name: 'idx_venues_review_status')
      remove_index :venues, name: 'idx_venues_review_reason' if index_exists?(:venues, :review_rejection_reason, name: 'idx_venues_review_reason')
      remove_index :venues, name: 'idx_venues_reviewed_at' if index_exists?(:venues, :reviewed_at, name: 'idx_venues_reviewed_at')
      remove_index :venues, name: 'idx_venues_reviewed_by' if index_exists?(:venues, :reviewed_by_id, name: 'idx_venues_reviewed_by')

      remove_column :venues, :review_status if column_exists?(:venues, :review_status)
      remove_column :venues, :review_rejection_reason if column_exists?(:venues, :review_rejection_reason)
      remove_column :venues, :review_rejection_note if column_exists?(:venues, :review_rejection_note)
      remove_column :venues, :reviewed_at if column_exists?(:venues, :reviewed_at)
      remove_column :venues, :reviewed_by_id if column_exists?(:venues, :reviewed_by_id)
    end
  end

  private

  def add_venue_review_columns
    return unless table_exists?(:venues)

    add_column :venues, :review_status, :string, null: false, default: 'pending' unless column_exists?(:venues, :review_status)
    add_column :venues, :review_rejection_reason, :string unless column_exists?(:venues, :review_rejection_reason)
    add_column :venues, :review_rejection_note, :text unless column_exists?(:venues, :review_rejection_note)
    add_column :venues, :reviewed_at, :datetime unless column_exists?(:venues, :reviewed_at)
    add_column :venues, :reviewed_by_id, :bigint unless column_exists?(:venues, :reviewed_by_id)

    add_index :venues, :review_status, name: 'idx_venues_review_status' unless index_exists?(:venues, :review_status, name: 'idx_venues_review_status')
    add_index :venues, :review_rejection_reason, name: 'idx_venues_review_reason' unless index_exists?(:venues, :review_rejection_reason, name: 'idx_venues_review_reason')
    add_index :venues, :reviewed_at, name: 'idx_venues_reviewed_at' unless index_exists?(:venues, :reviewed_at, name: 'idx_venues_reviewed_at')
    add_index :venues, :reviewed_by_id, name: 'idx_venues_reviewed_by' unless index_exists?(:venues, :reviewed_by_id, name: 'idx_venues_reviewed_by')

    unless foreign_key_exists?(:venues, :users, column: :reviewed_by_id)
      add_foreign_key :venues, :users, column: :reviewed_by_id, name: 'fk_venues_reviewed_by', on_delete: :nullify
    end
  end

  def create_review_batches
    return if table_exists?(:black_coffee_review_batches)

    create_table :black_coffee_review_batches do |t|
      t.string :status, null: false, default: 'open'
      t.json :filters_payload
      t.integer :batch_size, null: false, default: 100
      t.integer :total_places, null: false, default: 0
      t.integer :approved_count, null: false, default: 0
      t.integer :rejected_count, null: false, default: 0
      t.datetime :reviewed_at
      t.bigint :reviewed_by_id
      t.timestamps
    end

    add_index :black_coffee_review_batches, :status, name: 'idx_bc_review_batches_status'
    add_index :black_coffee_review_batches, :reviewed_at, name: 'idx_bc_review_batches_reviewed_at'
    add_index :black_coffee_review_batches, :reviewed_by_id, name: 'idx_bc_review_batches_reviewer'

    add_foreign_key :black_coffee_review_batches,
                    :users,
                    column: :reviewed_by_id,
                    name: 'fk_bc_review_batches_reviewer',
                    on_delete: :nullify
  end

  def create_review_batch_items
    return if table_exists?(:black_coffee_review_batch_items)

    create_table :black_coffee_review_batch_items do |t|
      t.bigint :black_coffee_review_batch_id, null: false
      t.string :venue_id, null: false
      t.string :review_status, null: false, default: 'pending'
      t.string :review_rejection_reason
      t.text :review_rejection_note
      t.datetime :reviewed_at
      t.timestamps
    end

    add_index :black_coffee_review_batch_items,
              :black_coffee_review_batch_id,
              name: 'idx_bc_review_items_batch'
    add_index :black_coffee_review_batch_items,
              [:black_coffee_review_batch_id, :venue_id],
              unique: true,
              name: 'idx_bc_review_items_batch_venue'
    add_index :black_coffee_review_batch_items, :venue_id, name: 'idx_bc_review_items_venue'
    add_index :black_coffee_review_batch_items, :review_status, name: 'idx_bc_review_items_status'
    add_index :black_coffee_review_batch_items, :review_rejection_reason, name: 'idx_bc_review_items_reason'

    add_foreign_key :black_coffee_review_batch_items,
                    :black_coffee_review_batches,
                    column: :black_coffee_review_batch_id,
                    name: 'fk_bc_review_items_batch',
                    on_delete: :cascade
    add_foreign_key :black_coffee_review_batch_items,
                    :venues,
                    column: :venue_id,
                    name: 'fk_bc_review_items_venue',
                    on_delete: :cascade
  end
end
