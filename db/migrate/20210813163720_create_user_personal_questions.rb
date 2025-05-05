class CreateUserPersonalQuestions < ActiveRecord::Migration[6.0]
  def change
    create_table :user_personal_questions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :personal_question, null: false, foreign_key: true
      t.text :answer

      t.timestamps
    end
  end
end
