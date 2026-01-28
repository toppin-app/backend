class Complaint < ApplicationRecord
  belongs_to :user
  belongs_to :reported_user, class_name: 'User', foreign_key: 'to_user_id'

  ACTION_OPTIONS = [
    ['Sin acción', 'no_action'],
    ['Usuario bloqueado', 'user_blocked'],
    ['Denuncia ignorada', 'invalidated']
  ].freeze

  enum action_taken: {
    no_action: 'no_action',
    user_blocked: 'user_blocked',
    invalidated: 'invalidated'
  }
  
  # El estado se calcula automáticamente basado en la acción
  before_save :update_status
  
  # Scopes para filtrar por estado
  scope :recent, -> { order(created_at: :desc) }
  scope :by_reason, ->(reason) { where(reason: reason) if reason.present? }
  
  private
  
  def update_status
    self.status = action_taken == 'no_action' ? 'unreviewed' : 'reviewed'
  end
end
