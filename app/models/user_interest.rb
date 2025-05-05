class UserInterest < ApplicationRecord
  belongs_to :interest
  belongs_to :user
  validates :interest_id, uniqueness: { scope: :user_id }

  before_save :set_name
  after_create :update_user

  def update_user
      self.user.update(updated_at: DateTime.now)
  end

  # Nos guardamos el nombre del interés por cuestión de optimización.
  def set_name
        self.interest_name = self.interest.name
  end


end
  