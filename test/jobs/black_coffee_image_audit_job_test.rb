require 'test_helper'

class BlackCoffeeImageAuditJobTest < ActiveJob::TestCase
  test 'ignores stale worker tokens' do
    batch = BlackCoffeeImageAuditBatch.create!(
      status: 'running',
      processing_mode: 'server',
      worker_token: 'current-token',
      total_venues: 1,
      total_images: 1
    )

    BlackCoffeeImageAuditJob.new.perform(batch.id, 1, 'stale-token')

    batch.reload
    assert_nil batch.last_worker_heartbeat_at
    assert_equal 'running', batch.status
  end
end
