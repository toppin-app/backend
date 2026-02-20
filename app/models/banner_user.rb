class BannerUser < ApplicationRecord
  belongs_to :banner
  belongs_to :user

  # REMOVED: validates :banner_id, uniqueness: { scope: :user_id }
  # Permitir múltiples impresiones del mismo banner por usuario (como publis)
  
  # Cada registro representa una ENTREGA específica de un banner a un usuario
  # - Se crea en el momento que se entrega (GET /get_banner)
  # - Se marca como visto cuando se renderiza (PUT /mark_banner_viewed)
  # - Se marca como abierto cuando se hace clic (PUT /mark_banner_opened)
end