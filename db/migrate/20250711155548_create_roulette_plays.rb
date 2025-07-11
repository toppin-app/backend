class CreateRoulettePlays < ActiveRecord::Migration[6.0]
  def change
    create_table :roulette_plays do |t|
      t.integer :user_id, null: false
      t.integer :spin_number, null: false
      t.string :result, null: false

      t.timestamps
    end

    add_index :roulette_plays, :user_id
  end
end