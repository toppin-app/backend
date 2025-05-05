class CreateUserFilterPreferences < ActiveRecord::Migration[6.0]
  def change
    create_table :user_filter_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :gender
      t.integer :distance_range
      t.integer :age_from
      t.integer :age_till

      t.timestamps
    end
  end
end
