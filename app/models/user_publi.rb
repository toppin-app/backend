class UserPubli < ApplicationRecord
  self.table_name = 'users_publis'

  belongs_to :user
  belongs_to :publi
end