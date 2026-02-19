class Banner < ApplicationRecord
  has_many :banner_users, dependent: :destroy
  has_many :users, through: :banner_users

  # Agregar CarrierWave para subir archivos
  mount_uploader :image, ImageUploader

  validates :title, presence: true
  validates :url, presence: true

  scope :active, -> { where(active: true) }
  scope :current, -> { where('start_date IS NULL OR start_date <= ?', Time.current).where('end_date IS NULL OR end_date >= ?', Time.current) }
  scope :active_now, -> { active.current }

  def viewed_by_user?(user)
    banner_users.exists?(user: user)
  end

  def mark_as_viewed_by(user)
    Rails.logger.info "=== MARK_AS_VIEWED_BY ==="
    Rails.logger.info "Banner ID: #{self.id}"
    Rails.logger.info "User ID: #{user.id}"
    
    # Crear siempre un nuevo registro (múltiples impresiones como publis)
    new_record = banner_users.create(user: user, viewed: true, viewed_at: Time.current)
    
    if new_record.persisted?
      Rails.logger.info "✅ Registro creado exitosamente: banner_user ID #{new_record.id}"
    else
      Rails.logger.error "❌ Error al crear registro: #{new_record.errors.full_messages.join(', ')}"
    end
    
    Rails.logger.info "Total registros para este banner: #{banner_users.count}"
    new_record
  end
end