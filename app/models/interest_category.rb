class InterestCategory < ApplicationRecord
  has_many :interests

  def interest_values
    self.interests
  end
end
