# Ejecuta: rails generate migration ChangeImageUrlToImageInBanners
class ChangeImageUrlToImageInBanners < ActiveRecord::Migration[6.0]
  def change
    remove_column :banners, :image_url, :string
    add_column :banners, :image, :string
  end
end