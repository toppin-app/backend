class CreateComplaints < ActiveRecord::Migration[6.0]
  def change
    create_table :complaints do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :to_user_id
      t.string :reason
      t.text :text

      t.timestamps
    end
  end
end
