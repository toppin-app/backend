class UserMatchRequest < ApplicationRecord
  belongs_to :user
  has_many :user_media, through: :user

  scope :rejected, -> (user_id) {
    where("(user_id = ? or target_user = ?) and is_rejected is true", user_id, user_id)
  }

  def target
    us = User.find_by(id: target_user)
    if !us
      self.destroy
      return
    else
      return us
    end
  end

  def self.ranking
    UserMatchRequest.all.each do |umr|
      umr.user_ranking = umr.user.ranking
      umr.target_user_ranking = umr.target.ranking
      umr.save
    end
  end

  # Busca un match_request entre dos usuarios.
  def self.match_between(user1, user2)
    # Prioriza solicitud del user1 al user2
    exact = where(user_id: user1, target_user: user2).order(created_at: :desc).first
    return exact if exact.present?

    # Si no hay, busca la inversa
    inverse = where(user_id: user2, target_user: user1).order(created_at: :desc).first
    return inverse
  end

  # Comprueba si existe un match confirmado entre dos usuarios
  def self.match_confirmed_between?(user_a, user_b)
    where(
      is_match: true,
      user_id: [user_a, user_b],
      target_user: [user_a, user_b]
    ).exists?
  end
end
