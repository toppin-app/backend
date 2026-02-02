class Complaint < ApplicationRecord
  belongs_to :user
  belongs_to :reported_user, class_name: 'User', foreign_key: 'to_user_id', optional: true

  # Constantes de reason_key (sincronizadas con la app móvil)
  REASON_KEYS = {
    inappropriate_content: 'inappropriate_content',
    spam: 'spam',
    fake_profile: 'fake_profile',
    harassment: 'harassment',
    underage: 'underage',
    other: 'other'
  }.freeze

  REASON_KEY_LABELS = {
    'inappropriate_content' => 'Contenido inapropiado',
    'spam' => 'Spam',
    'fake_profile' => 'Perfil falso',
    'harassment' => 'Acoso',
    'underage' => 'Menor de edad',
    'other' => 'Otro'
  }.freeze

  # Validación: solo requerir reported_user si la acción es bloquearlo
  validate :validate_reported_user_for_action
  
  def validate_reported_user_for_action
    if action_taken == 'user_blocked' && reported_user.blank?
      errors.add(:action_taken, "no se puede aplicar porque el usuario denunciado ya no existe. Marca la denuncia como ignorada.")
    end
  end

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
  after_save :update_user_block_reason
  after_create :block_reported_user_if_requested
  
  # Scopes para filtrar por estado
  scope :recent, -> { order(created_at: :desc) }
  scope :by_reason, ->(reason) { where(reason: reason) if reason.present? }
  
  private
  
  def update_status
    self.status = action_taken == 'no_action' ? 'unreviewed' : 'reviewed'
  end
  
  def update_user_block_reason
    if action_taken == 'user_blocked' && reported_user.present? && reason_key.present?
      reported_user.update_column(:block_reason_key, reason_key)
    end
  end
  
  # Bloquear al usuario denunciado si se solicitó al crear la denuncia
  def block_reported_user_if_requested
    if block_user && reported_user.present?
      # Crear bloqueo solo si no existe ya
      unless user.blocks.exists?(blocked_user_id: reported_user.id)
        user.blocks.create(blocked_user_id: reported_user.id)
      end
    end
  end
end
