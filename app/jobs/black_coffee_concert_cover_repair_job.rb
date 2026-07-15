class BlackCoffeeConcertCoverRepairJob < ApplicationJob
  queue_as :default

  REENQUEUE_DELAY = 1.second

  def perform(batch_id, limit = BlackCoffeeConcertCoverRepairRunner::DEFAULT_LIMIT, worker_token = nil)
    batch = BlackCoffeeConcertCoverRepairBatch.find_by(id: batch_id)
    return unless runnable_batch?(batch, worker_token)

    mark_heartbeat!(batch)
    BlackCoffeeConcertCoverRepairRunner.advance!(batch: batch, limit: limit)
    batch.reload
    return unless runnable_batch?(batch, worker_token)
    return unless batch.pending_items?

    mark_heartbeat!(batch)
    self.class.set(wait: REENQUEUE_DELAY).perform_later(batch.id, limit, worker_token)
  rescue StandardError => e
    fail_batch!(batch_id, e)
    Rails.logger.error "Black Coffee concert cover repair job failed: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if e.backtrace
  end

  private

  def runnable_batch?(batch, worker_token)
    return false unless batch
    return false if batch.finished?
    return false if worker_token.present? && batch.worker_token != worker_token

    true
  end

  def mark_heartbeat!(batch)
    batch.update_columns(
      status: 'running',
      started_at: batch.started_at || Time.current,
      last_worker_heartbeat_at: Time.current,
      updated_at: Time.current
    )
  end

  def fail_batch!(batch_id, error)
    batch = BlackCoffeeConcertCoverRepairBatch.find_by(id: batch_id)
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
