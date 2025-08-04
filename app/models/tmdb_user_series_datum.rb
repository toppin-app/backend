class TmdbUserSeriesDatum < ApplicationRecord
  belongs_to :user

  # Puedes agregar validaciones si lo necesitas, por ejemplo:
  # validates :tmdb_id, presence: true
end
