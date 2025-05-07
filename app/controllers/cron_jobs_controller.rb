class CronJobsController < ApplicationController
  before_action :validate_cron_token

  def regenerate_superlike
    User.where(superlike_available: 0, current_subscription_name: nil).where("last_superlike_given <= ?", DateTime.now - 7.days).update_all(superlike_available: 1)
    User.where(superlike_available: 0).where.not(current_subscription_name: nil).where("last_superlike_given <= ?", DateTime.now - 7.days).update_all(superlike_available: 5)
    render json: "OK".to_json
  end

  def check_outdated_boosts
    users = User.where(high_visibility: true).where("high_visibility_expire <= ?", DateTime.now)
    users.each do |user|
      user.update(high_visibility: false)
      Device.sendIndividualPush(user.id, "Tu power sweet ha finalizado", "", "boost_ended")
    end
    render json: "OK".to_json
  end

  def recalculate_popularity
    User.active.each(&:recalculate_popularity)
    render json: "OK".to_json
  end

  private

  def validate_cron_token
    head :unauthorized unless params[:token] == ENV['CRON_TOKEN']
  end
end