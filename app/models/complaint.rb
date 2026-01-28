class Complaint < ApplicationRecord
  belongs_to :user
  belongs_to :reported_user, class_name: 'User', foreign_key: 'to_user_id'
  
  # Scopes para filtrar por estado
  scope :recent, -> { order(created_at: :desc) }
  scope :by_reason, ->(reason) { where(reason: reason) if reason.present? }
end
