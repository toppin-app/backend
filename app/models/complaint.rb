class Complaint < ApplicationRecord
  belongs_to :user
  belongs_to :reported_user, class_name: 'User', foreign_key: 'to_user_id'

  STATUS_OPTIONS = [
    ['Sin revisar', 'unreviewed'],
    ['Revisado', 'reviewed']
  ].freeze

  ACTION_OPTIONS = [
    ['Sin acción', 'no_action'],
    ['Usuario bloqueado', 'user_blocked'],
    ['Denuncia invalidada', 'invalidated']
  ].freeze

  enum status: {
    unreviewed: 'unreviewed',
    reviewed: 'reviewed'
  }

  enum action_taken: {
    no_action: 'no_action',
    user_blocked: 'user_blocked',
    invalidated: 'invalidated'
  }
  
  # Scopes para filtrar por estado
  scope :recent, -> { order(created_at: :desc) }
  scope :by_reason, ->(reason) { where(reason: reason) if reason.present? }
end
