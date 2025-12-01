class RecalculateRankingJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user
    
    user.recalculate_ranking
    Rails.logger.info "✅ Ranking recalculado para usuario #{user_id}"
  rescue => e
    Rails.logger.error "❌ Error recalculando ranking: #{e.message}"
  end
end
