class BlackCoffeeReviewBatchItem < ApplicationRecord
  belongs_to :review_batch,
             class_name: 'BlackCoffeeReviewBatch',
             foreign_key: :black_coffee_review_batch_id,
             inverse_of: :review_items
  belongs_to :venue

  validates :review_status, inclusion: { in: Venue::REVIEW_STATUSES }
  validates :review_rejection_reason, inclusion: { in: Venue::REJECTION_REASON_CODES }, allow_blank: true
  validates :category_correction_from, inclusion: { in: Venue::CATEGORIES }, allow_blank: true
  validates :category_correction_to, inclusion: { in: Venue::CATEGORIES }, allow_blank: true
  validates :venue_id, uniqueness: { scope: :black_coffee_review_batch_id }

  scope :ordered, -> { order(:id) }

  def rejected?
    review_status == Venue::REVIEW_STATUS_REJECTED
  end

  def approved?
    review_status == Venue::REVIEW_STATUS_APPROVED
  end

  def review_status_label
    Venue.review_status_label_for(review_status)
  end

  def rejection_reason_label
    Venue.rejection_reason_label(review_rejection_reason)
  end

  def category_corrected?
    category_correction_from.present? && category_correction_to.present?
  end
end
