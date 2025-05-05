class UserMainInterest < ApplicationRecord
  belongs_to :user
  belongs_to :interest

  before_save :copy_interest_name

  private

  def copy_interest_name
    self.name = interest.name
  end
end
