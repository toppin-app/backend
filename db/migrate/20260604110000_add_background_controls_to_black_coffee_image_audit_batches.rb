class AddBackgroundControlsToBlackCoffeeImageAuditBatches < ActiveRecord::Migration[6.0]
  def change
    return unless table_exists?(:black_coffee_image_audit_batches)

    unless column_exists?(:black_coffee_image_audit_batches, :review_status_filter)
      add_column :black_coffee_image_audit_batches,
                 :review_status_filter,
                 :string,
                 null: false,
                 default: 'pending'
    end

    unless column_exists?(:black_coffee_image_audit_batches, :processing_mode)
      add_column :black_coffee_image_audit_batches,
                 :processing_mode,
                 :string,
                 null: false,
                 default: 'manual'
    end

    add_column :black_coffee_image_audit_batches, :background_started_at, :datetime unless column_exists?(:black_coffee_image_audit_batches, :background_started_at)
    add_column :black_coffee_image_audit_batches, :last_worker_heartbeat_at, :datetime unless column_exists?(:black_coffee_image_audit_batches, :last_worker_heartbeat_at)
    add_column :black_coffee_image_audit_batches, :background_requested_limit, :integer unless column_exists?(:black_coffee_image_audit_batches, :background_requested_limit)
    add_column :black_coffee_image_audit_batches, :worker_token, :string unless column_exists?(:black_coffee_image_audit_batches, :worker_token)

    unless index_exists?(:black_coffee_image_audit_batches, :review_status_filter, name: 'idx_bc_image_audit_batches_review_filter')
      add_index :black_coffee_image_audit_batches,
                :review_status_filter,
                name: 'idx_bc_image_audit_batches_review_filter'
    end

    unless index_exists?(:black_coffee_image_audit_batches, :processing_mode, name: 'idx_bc_image_audit_batches_mode')
      add_index :black_coffee_image_audit_batches,
                :processing_mode,
                name: 'idx_bc_image_audit_batches_mode'
    end
  end
end
