class CreatePersonalQuestions < ActiveRecord::Migration[6.0]
  def change
    create_table :personal_questions do |t|
      t.string :name

      t.timestamps
    end
  end
end
