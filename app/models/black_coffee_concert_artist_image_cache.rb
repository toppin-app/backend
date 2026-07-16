class BlackCoffeeConcertArtistImageCache < ApplicationRecord
  STATUSES = %w[pending resolved not_found ambiguous retryable_error unavailable].freeze

  belongs_to :venue_image, optional: true

  validates :identity_key, :artist_name, :canonical_name, presence: true
  validates :identity_key, uniqueness: { case_sensitive: true }
  validates :status, inclusion: { in: STATUSES }

  scope :resolved, -> { where(status: 'resolved') }
  scope :searchable_again, -> { where('retry_after IS NULL OR retry_after <= ?', Time.current) }

  def fresh?(at: Time.current)
    return false if retry_after.present? && retry_after <= at
    return false if expires_at.present? && expires_at <= at

    searched_at.present?
  end

  def reusable_binary?
    resolved? && venue_image&.uploaded_image?
  end

  def resolved?
    status == 'resolved'
  end

  def negative?
    %w[not_found ambiguous].include?(status)
  end

  def retryable_error?
    status == 'retryable_error'
  end
end
