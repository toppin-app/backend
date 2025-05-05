class Interest < ApplicationRecord
  belongs_to :interest_category
  has_many :user_main_interests, dependent: :destroy

  def name_with_category
   self.interest_category.name+" : "+name
  end

end
