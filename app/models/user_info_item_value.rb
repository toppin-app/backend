class UserInfoItemValue < ApplicationRecord
  belongs_to :user
  belongs_to :info_item_value

  validates :info_item_value_id, uniqueness: { scope: :user_id }

  before_save :set_name, :set_item_name # Guardamos el nombre de la categoría y del item antes de guardar. Nos ayuda a optimizar después.
  after_create :update_user

  def update_user
      self.user.update(updated_at: DateTime.now)
  end



  def set_name
      self.category_name = self.info_item_value.info_item_category.name     
  end

  def set_item_name
      self.item_name = self.info_item_value.value
  end




end
