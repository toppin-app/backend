class AddCategoryCorrectionToBlackCoffeeReviewItems < ActiveRecord::Migration[6.0]
  def change
    return unless table_exists?(:black_coffee_review_batch_items)

    unless column_exists?(:black_coffee_review_batch_items, :category_correction_from)
      add_column :black_coffee_review_batch_items, :category_correction_from, :string
    end

    unless column_exists?(:black_coffee_review_batch_items, :category_correction_to)
      add_column :black_coffee_review_batch_items, :category_correction_to, :string
    end

    unless column_exists?(:black_coffee_review_batch_items, :venue_subcategory_correction_from_id)
      add_column :black_coffee_review_batch_items, :venue_subcategory_correction_from_id, :bigint
    end
  end
end
