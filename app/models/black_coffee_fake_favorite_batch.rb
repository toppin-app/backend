class BlackCoffeeFakeFavoriteBatch < ApplicationRecord
  STATUSES = %w[pending running completed failed cancelled].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending running]) }
  scope :recent_first, -> { order(created_at: :desc) }

  def user_ids
    normalized_integer_array(user_ids_payload)
  end

  def pending_user_ids
    normalized_integer_array(pending_user_ids_payload)
  end

  def failed_user_ids
    normalized_integer_array(failed_user_ids_payload)
  end

  def states
    normalized_string_array(states_payload)
  end

  def categories
    normalized_string_array(categories_payload)
  end

  def combination_entries
    Array(combination_entries_payload).filter_map do |entry|
      next unless entry.respond_to?(:[])

      state_key = entry['state_key'] || entry[:state_key]
      category = entry['category'] || entry[:category]
      label = entry['label'] || entry[:label]
      venue_ids = normalized_integer_array(entry['venue_ids'] || entry[:venue_ids])
      next if category.to_s.strip.blank?

      {
        'state_key' => BlackCoffeeVenueCombinationMatrix.normalize_state_key(state_key),
        'category' => category.to_s.strip,
        'label' => label.to_s.strip.presence || BlackCoffeeVenueCombinationMatrix.combination_label(state_key, category),
        'venue_ids' => venue_ids
      }
    end
  end

  def empty_combinations
    Array(empty_combinations_payload).filter_map do |entry|
      next unless entry.respond_to?(:[])

      state_key = entry['state_key'] || entry[:state_key]
      category = entry['category'] || entry[:category]
      label = entry['label'] || entry[:label]
      next if category.to_s.strip.blank?

      {
        'state_key' => BlackCoffeeVenueCombinationMatrix.normalize_state_key(state_key),
        'category' => category.to_s.strip,
        'label' => label.to_s.strip.presence || BlackCoffeeVenueCombinationMatrix.combination_label(state_key, category)
      }
    end
  end

  def active?
    status.in?(%w[pending running])
  end

  def finished?
    status.in?(%w[completed failed cancelled])
  end

  def retryable?
    status == 'failed'
  end

  def completion_percentage
    total = total_users_count.to_i
    return 0 if total.zero?

    ((processed_users_count.to_f / total) * 100).round
  end

  def as_progress_json
    {
      id: id,
      status: status,
      active: active?,
      finished: finished?,
      retryable: retryable?,
      totalUsers: total_users_count.to_i,
      pendingUsers: pending_users_count.to_i,
      processedUsers: processed_users_count.to_i,
      failedUsers: failed_users_count.to_i,
      deletedFavorites: deleted_favorites_count.to_i,
      createdFavorites: created_favorites_count.to_i,
      combinationsCount: combinations_count.to_i,
      combinationsWithoutVenues: combinations_without_venues_count.to_i,
      completionPercentage: completion_percentage,
      currentUserId: current_user_id,
      currentUserName: current_user_name,
      lastProcessedUserId: last_processed_user_id,
      lastProcessedUserName: last_processed_user_name,
      favoritesResetAt: favorites_reset_at,
      startedAt: started_at,
      lastAdvancedAt: last_advanced_at,
      finishedAt: finished_at,
      errorMessage: error_message,
      emptyCombinationLabels: empty_combinations.map { |entry| entry['label'] }
    }
  end

  private

  def normalized_integer_array(value)
    Array(value).filter_map do |entry|
      normalized = entry.to_s.strip
      next if normalized.blank?

      normalized.to_i
    end.uniq
  end

  def normalized_string_array(value)
    Array(value).map { |entry| entry.to_s.strip }.reject(&:blank?).uniq
  end
end
