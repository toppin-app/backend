class CreateUserMedia < ActiveRecord::Migration[6.0]
  def change
    create_table :user_media do |t|
      t.references :user, null: false, foreign_key: true
      t.string :file
      t.integer :position

      t.timestamps
    end
  end
end
