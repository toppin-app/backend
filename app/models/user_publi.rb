class UserPubli < ApplicationRecord
  self.table_name = 'users_publis'

  belongs_to :user
  belongs_to :publi
  
  before_create :copy_user_location
  
  private
  
  def copy_user_location
    self.locality = user.locality
    self.country = user.country
    self.lat = user.lat
    self.lng = user.lng
  end
end