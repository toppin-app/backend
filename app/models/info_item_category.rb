class InfoItemCategory < ApplicationRecord
  has_many :info_item_values, dependent: :destroy

  def info_items_with_values
    self.info_item_values
  end
end
