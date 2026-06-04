class BlackCoffeeImageAuditJob < ApplicationJob
  queue_as :default

  REENQUEUE_DELAY = 1.second

  def perform(batch_id, limit = BlackCoffeePendingImageAuditRunner::DEFAULT_LIMIT, worker_token = nil)
    batch = BlackCoffeeImageAuditBatch.find_by(id: batch_id)
    return unless runnable_batch?(batch, worker_token)

    mark_heartbeat!(batch, limit)
    BlackCoffeePendingImageAuditRunner.advance!(batch: batch, limit: limit)
    batch.reload
    return unless runnable_batch?(batch, worker_token)
    return unless batch.pending_checks?

    mark_heartbeat!(batch, limit)
    self.class.set(wait: REENQUEUE_DELAY).perform_later(batch.id, limit, worker_token)
  rescue StandardError => e
    fail_batch!(batch_id, e)
    Rails.logger.error "Black Coffee image audit job failed: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if e.backtrace
  end

  private

  def runnable_batch?(batch, worker_token)
    return false unless batch
    return false if batch.finished?
    return false if batch.has_attribute?(:worker_token) && worker_token.present? && batch.worker_token != worker_token

    true
  end

  def mark_heartbeat!(batch, limit)
    batch.update_columns(
      status: 'running',
      processing_mode: 'server',
      background_started_at: batch.background_started_at || Time.current,
      background_requested_limit: limit.to_i,
      last_worker_heartbeat_at: Time.current,
      updated_at: Time.current
    )
  end

  def fail_batch!(batch_id, error)
    batch = BlackCoffeeImageAuditBatch.find_by(id: batch_id)
    return unless batch
    return if batch.finished?

    batch.update_columns(
      status: 'failed',
      error_message: "Error del job de servidor: #{error.class} - #{error.message}",
      last_worker_heartbeat_at: Time.current,
      updated_at: Time.current
    )
  end
end
