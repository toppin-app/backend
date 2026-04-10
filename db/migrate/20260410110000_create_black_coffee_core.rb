class CreateBlackCoffeeCore < ActiveRecord::Migration[6.0]
  def change
    create_table :venue_subcategories, id: :string do |t|
      t.string :name, null: false
      t.string :category, null: false

      t.timestamps
    end

    add_index :venue_subcategories, [:category, :name], unique: true

    create_table :venues, id: :string do |t|
      t.string :name, null: false
      t.string :category, null: false
      t.references :venue_subcategory, type: :string, foreign_key: { on_delete: :nullify }
      t.text :description, null: false
      t.string :address, null: false
      t.string :city, null: false
      t.decimal :latitude, precision: 10, scale: 7, null: false
      t.decimal :longitude, precision: 10, scale: 7, null: false
      t.integer :favorites_count, null: false, default: 0
      t.boolean :featured, null: false, default: false
      t.json :tags

      t.timestamps
    end

    add_index :venues, :category
    add_index :venues, :featured
    add_index :venues, :favorites_count
    add_index :venues, [:latitude, :longitude]

    create_table :venue_images do |t|
      t.references :venue, type: :string, null: false, foreign_key: true
      t.string :url, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :venue_images, [:venue_id, :position], unique: true

    create_table :venue_schedules do |t|
      t.references :venue, type: :string, null: false, foreign_key: true
      t.string :day, null: false, limit: 1
      t.boolean :closed, null: false, default: false
      t.time :slot_open
      t.time :slot_close
      t.integer :slot_index, null: false, default: 0

      t.timestamps
    end

    add_index :venue_schedules, [:venue_id, :day, :slot_index], unique: true

    create_table :user_favorites do |t|
      t.references :user, null: false, foreign_key: true
      t.references :venue, type: :string, null: false, foreign_key: true

      t.timestamps
    end

    add_index :user_favorites, [:user_id, :venue_id], unique: true
  end
end
