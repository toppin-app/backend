class CreateUserMainInterests < ActiveRecord::Migration[6.0]
  def change
    create_table :user_main_interests do |t|
      t.bigint :user_id
      t.bigint :interest_id
      t.integer :percentage
      t.string :name

      t.timestamps
    end
  end
end
