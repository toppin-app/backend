class UserMatchRequest < ApplicationRecord
  belongs_to :user
  has_many :user_media, through: :user

  scope :rejected, -> (user_id)  { where("(user_id = ? or target_user = ?) and is_rejected is true", user_id, user_id) }

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

     result = UserMatchRequest.where("(user_id = ? AND target_user = ?) or (user_id = ? and target_user = ?)", user1, user2, user2, user1)
    
     if result.any?
      return result.last
     else
      return nil
    end


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
