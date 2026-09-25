Sequel.migration do
  up do
    create_table(:event_excusals) do
      primary_key :id
      foreign_key :event_id, :events, null: false, on_delete: :cascade
      Integer :student_id, null: false
      unique [:event_id, :student_id]
    end
  end

  down do
    drop_table(:event_excusals)
  end
end
