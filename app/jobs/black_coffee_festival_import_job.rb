class BlackCoffeeFestivalImportJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = BlackCoffeeFestivalImportRun.find_by(id: run_id)
    return unless run
    return if run.finished?

    FanMusicFest::Importer.new(run: run).perform!
  rescue StandardError => e
    fail_run!(run_id, e)
    Rails.logger.error "Black Coffee FanMusicFest import job failed: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if e.backtrace
  end

  private

  def fail_run!(run_id, error)
    run = BlackCoffeeFestivalImportRun.find_by(id: run_id)
    return unless run
    return if run.finished?

    run.update_columns(
      status: 'failed',
      error_message: "Error del job de servidor: #{error.class} - #{error.message}",
      completed_at: Time.current,
      updated_at: Time.current
    )
  end
end
