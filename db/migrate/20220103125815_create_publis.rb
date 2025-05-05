class CreatePublis < ActiveRecord::Migration[6.0]
  def change
    create_table :publis do |t|
      t.string :title
      t.datetime :start_date
      t.datetime :end_date
      t.string :weekdays
      t.time :start_time
      t.time :end_time
      t.string :image
      t.string :video
      t.string :link
      t.boolean :cancellable, default: true
      t.integer :repeat_swipes, default: 30

      t.timestamps
    end
  end
end
