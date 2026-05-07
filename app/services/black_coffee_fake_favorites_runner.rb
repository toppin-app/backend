class BlackCoffeeFakeFavoritesRunner
  DEFAULT_STEP_BUDGET = 10
  DEFAULT_TIME_BUDGET_SECONDS = 6
  MAX_CLAIM_WINDOW = 5
  MAX_ERROR_MESSAGE_LENGTH = 1_000

  def self.start!
    active_batch = BlackCoffeeFakeFavoriteBatch.active.recent_first.first
    return active_batch if active_batch.present?

    user_ids = User.fake_users.active_accounts.order(:id).pluck(:id)
    raise 'No hay usuarios fake activos para regenerar favoritos.' if user_ids.empty?

    matrix = BlackCoffeeVenueCombinationMatrix.build(scope: Venue.public_catalog_scope)
    raise 'No hay locales Black Coffee publicables para generar favoritos fake.' if matrix.populated_combination_keys.empty?

    combination_entries = matrix.populated_combination_keys.map do |state_key, category|
      {
        state_key: state_key,
        category: category,
        label: BlackCoffeeVenueCombinationMatrix.combination_label(state_key, category),
        venue_ids: Array(matrix.venue_ids_by_combination[[state_key, category]]).map(&:to_i).uniq
      }
    end

    empty_combinations = matrix.empty_combination_keys.map do |state_key, category|
      {
        state_key: state_key,
        category: category,
        label: BlackCoffeeVenueCombinationMatrix.combination_label(state_key, category)
      }
    end

    Rails.logger.info(
      "[BlackCoffeeFakeFavoritesRunner] Preparando lote. fake_users=#{user_ids.size}, ubicaciones=#{matrix.states.size}, categorias=#{matrix.categories.size}, combinaciones=#{matrix.combination_keys.size}, vacias=#{empty_combinations.size}"
    )

    BlackCoffeeFakeFavoriteBatch.create!(
      status: 'pending',
      user_ids_payload: user_ids,
      pending_user_ids_payload: user_ids,
      failed_user_ids_payload: [],
      states_payload: matrix.states,
      categories_payload: matrix.categories,
      combination_entries_payload: combination_entries,
      empty_combinations_payload: empty_combinations,
      total_users_count: user_ids.size,
      pending_users_count: user_ids.size,
      combinations_count: matrix.combination_keys.size,
      combinations_without_venues_count: empty_combinations.size
    )
  end

  def self.advance!(batch:, step_budget: DEFAULT_STEP_BUDGET, time_budget_seconds: DEFAULT_TIME_BUDGET_SECONDS)
    new(batch).advance!(step_budget: step_budget, time_budget_seconds: time_budget_seconds)
  end

  def self.retry_failed!(batch:)
    new(batch).retry_failed!
  end

  def initialize(batch)
    @batch = batch
  end

  def advance!(step_budget:, time_budget_seconds:)
    return @batch if @batch.finished?

    ensure_fake_favorites_reset!

    started_at = monotonic_time
    processed_in_advance = 0

    loop do
      break if processed_in_advance >= step_budget
      break if processed_in_advance.positive? && elapsed_seconds(started_at) >= time_budget_seconds

      claim_limit = [step_budget - processed_in_advance, MAX_CLAIM_WINDOW].min
      claimed_ids = claim_user_ids(limit: claim_limit)
      break if claimed_ids.empty?

      chunk_result = process_claimed_users(
        claimed_ids: claimed_ids,
        started_at: started_at,
        time_budget_seconds: time_budget_seconds
      )
      processed_in_advance += chunk_result[:processed_count]
      persist_chunk_result!(chunk_result)
    end

    finalize_if_finished!
    @batch.reload
  end

  def retry_failed!
    user_ids = User.fake_users.active_accounts.where(id: @batch.user_ids).order(:id).pluck(:id)
    raise 'No quedan usuarios fake validos para volver a generar favoritos.' if user_ids.empty?

    BlackCoffeeFakeFavoriteBatch.transaction do
      @batch.lock!
      @batch.update!(
        status: 'pending',
        user_ids_payload: user_ids,
        pending_user_ids_payload: user_ids,
        failed_user_ids_payload: [],
        total_users_count: user_ids.size,
        pending_users_count: user_ids.size,
        processed_users_count: 0,
        failed_users_count: 0,
        deleted_favorites_count: 0,
        created_favorites_count: 0,
        current_user_id: nil,
        current_user_name: nil,
        last_processed_user_id: nil,
        last_processed_user_name: nil,
        favorites_reset_at: nil,
        started_at: nil,
        last_advanced_at: nil,
        finished_at: nil,
        error_message: nil
      )
    end

    Rails.logger.info("[BlackCoffeeFakeFavoritesRunner] Lote ##{@batch.id} reiniciado para regenerar favoritos fake desde cero.")
    @batch.reload
  end

  private

  def ensure_fake_favorites_reset!
    return if @batch.favorites_reset_at.present?

    deleted_count = 0

    BlackCoffeeFakeFavoriteBatch.transaction do
      @batch.lock!
      next if @batch.favorites_reset_at.present?

      user_ids = @batch.user_ids
      deleted_count = user_ids.any? ? UserFavorite.where(user_id: user_ids).delete_all : 0

      @batch.update!(
        favorites_reset_at: Time.current,
        deleted_favorites_count: deleted_count,
        status: 'pending',
        error_message: nil
      )
    end

    if deleted_count.positive?
      Rails.logger.info("[BlackCoffeeFakeFavoritesRunner] Lote ##{@batch.id}: se limpiaron #{deleted_count} favoritos previos de usuarios fake.")
    else
      Rails.logger.info("[BlackCoffeeFakeFavoritesRunner] Lote ##{@batch.id}: no habia favoritos fake previos que borrar.")
    end
  end

  def claim_user_ids(limit:)
    BlackCoffeeFakeFavoriteBatch.transaction do
      @batch.lock!
      return [] unless @batch.active?

      pending_ids = @batch.pending_user_ids
      claimed_ids = pending_ids.shift(limit)
      if claimed_ids.empty?
        @batch.update!(
          pending_user_ids_payload: pending_ids,
          current_user_id: nil,
          current_user_name: nil,
          last_advanced_at: Time.current
        )
        return []
      end

      @batch.update!(
        pending_user_ids_payload: pending_ids,
        status: 'running',
        started_at: @batch.started_at || Time.current,
        last_advanced_at: Time.current,
        current_user_id: claimed_ids.first,
        current_user_name: user_name_for(claimed_ids.first)
      )
      claimed_ids
    end
  end

  def process_claimed_users(claimed_ids:, started_at:, time_budget_seconds:)
    normalized_claimed_ids = Array(claimed_ids).map(&:to_i).uniq
    users_by_id = User.fake_users.active_accounts.where(id: normalized_claimed_ids).index_by(&:id)
    combination_entries = @batch.combination_entries

    result = {
      processed_count: 0,
      failed_count: 0,
      failed_ids: [],
      leftover_ids: [],
      created_count: 0,
      last_processed_user_id: nil,
      last_processed_user_name: nil,
      error_messages: []
    }

    normalized_claimed_ids.each_with_index do |user_id, index|
      if result[:processed_count].positive? && elapsed_seconds(started_at) >= time_budget_seconds
        result[:leftover_ids] = normalized_claimed_ids[index..-1]
        break
      end

      user = users_by_id[user_id]
      user_result = process_user(user, combination_entries)
      result[:processed_count] += 1
      result[:last_processed_user_id] = user_id
      result[:last_processed_user_name] = user&.name

      if user_result[:outcome] == :failed
        result[:failed_count] += 1
        result[:failed_ids] << user_id
        result[:error_messages] << user_result[:message] if user_result[:message].present?
      else
        result[:created_count] += user_result[:created_count].to_i
      end
    end

    result
  end

  def process_user(user, combination_entries)
    return { outcome: :failed, message: 'El usuario fake ya no existe o ya no esta activo.' } if user.blank?

    now = Time.current
    rows = combination_entries.filter_map do |entry|
      venue_ids = Array(entry['venue_ids']).map(&:to_i).uniq
      next if venue_ids.empty?

      sampled_venue_id = venue_ids.sample
      next if sampled_venue_id.blank?

      {
        user_id: user.id,
        venue_id: sampled_venue_id,
        created_at: now,
        updated_at: now
      }
    end

    unique_rows = rows.uniq { |row| row[:venue_id] }
    UserFavorite.insert_all(unique_rows) if unique_rows.any?

    {
      outcome: :created,
      created_count: unique_rows.size
    }
  rescue StandardError => e
    {
      outcome: :failed,
      message: "Usuario ##{user&.id || 'desconocido'}: #{e.message}"
    }
  end

  def persist_chunk_result!(chunk_result)
    BlackCoffeeFakeFavoriteBatch.transaction do
      @batch.lock!

      pending_ids = (chunk_result[:leftover_ids] + @batch.pending_user_ids).uniq
      failed_ids = (@batch.failed_user_ids + chunk_result[:failed_ids]).uniq
      processed_total = @batch.processed_users_count.to_i + chunk_result[:processed_count].to_i
      created_total = @batch.created_favorites_count.to_i + chunk_result[:created_count].to_i
      pending_total = pending_ids.size
      failed_total = failed_ids.size

      @batch.update!(
        pending_user_ids_payload: pending_ids,
        failed_user_ids_payload: failed_ids,
        pending_users_count: pending_total,
        processed_users_count: processed_total,
        failed_users_count: failed_total,
        created_favorites_count: created_total,
        current_user_id: pending_ids.first,
        current_user_name: user_name_for(pending_ids.first),
        last_processed_user_id: chunk_result[:last_processed_user_id],
        last_processed_user_name: chunk_result[:last_processed_user_name],
        last_advanced_at: Time.current,
        error_message: merge_error_messages(chunk_result[:error_messages])
      )
    end
  end

  def finalize_if_finished!
    BlackCoffeeFakeFavoriteBatch.transaction do
      @batch.lock!
      return if @batch.pending_user_ids.any?

      final_status = @batch.failed_user_ids.any? ? 'failed' : 'completed'
      @batch.update!(
        status: final_status,
        pending_users_count: 0,
        current_user_id: nil,
        current_user_name: nil,
        finished_at: Time.current,
        last_advanced_at: Time.current
      )
    end

    Rails.logger.info(
      "[BlackCoffeeFakeFavoritesRunner] Lote ##{@batch.id} finalizado con estado=#{@batch.reload.status}, usuarios=#{@batch.processed_users_count}, favoritos_creados=#{@batch.created_favorites_count}, errores=#{@batch.failed_users_count}"
    )
  end

  def merge_error_messages(new_messages)
    messages = Array(new_messages).map(&:to_s).map(&:strip).reject(&:blank?)
    return @batch.error_message if messages.empty?

    combined = [@batch.error_message.to_s.strip.presence, *messages].compact.uniq.join(' | ')
    combined.mb_chars.limit(MAX_ERROR_MESSAGE_LENGTH).to_s
  end

  def user_name_for(user_id)
    return nil if user_id.blank?

    User.where(id: user_id).pick(:name)
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def elapsed_seconds(start_time)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
  end
end
