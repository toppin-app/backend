class CreateTableUsersPublis < ActiveRecord::Migration[6.0]
  def change
    create_table :users_publis do |t|
      t.references :user, null: false, foreign_key: true
      t.references :publi, null: false, foreign_key: true
      t.boolean :viewed, default: false, null: false

      t.timestamps
    end
  end
end

