class AddReasonKeyToComplaints < ActiveRecord::Migration[6.0]
  def change
    add_column :complaints, :reason_key, :string
  end
end
