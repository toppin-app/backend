class InfoItemValue < ApplicationRecord
  belongs_to :info_item_category


  default_scope { order(value: :asc) }

  def name_with_category
    self.info_item_category.name+" : "+value
  end

end
