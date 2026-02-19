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
    # Crear siempre un nuevo registro (múltiples impresiones como publis)
    banner_users.create(user: user, viewed: true, viewed_at: Time.current)
  end
end