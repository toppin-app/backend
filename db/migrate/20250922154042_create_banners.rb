class CreateBanners < ActiveRecord::Migration[6.0]
  def change
    create_table :banners do |t|
      t.string :title, null: false
      t.text :description
      t.string :image_url, null: false
      t.string :url # URL a la que redirige cuando se hace click
      t.boolean :active, default: true
      t.datetime :start_date
      t.datetime :end_date
      
      t.timestamps
    end

    add_index :banners, :active
    add_index :banners, [:active, :start_date, :end_date]
  end
end