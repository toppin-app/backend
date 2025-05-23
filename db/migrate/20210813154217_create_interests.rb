class CreateInterests < ActiveRecord::Migration[6.0]
  def change
    create_table :interests do |t|
      t.references :interest_category, null: false, foreign_key: true
      t.string :name

      t.timestamps
    end
  end
end
