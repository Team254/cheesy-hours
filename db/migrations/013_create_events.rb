Sequel.migration do
  up do
    create_table(:events) do
      primary_key :id
      String :title, null: false
      Date :date, null: false
      Integer :check_in_code, null: false
      DateTime :closed_at
      Integer :created_by_bcp_id
      String :created_by_name, null: false
      index :date
    end

    create_table(:event_check_ins) do
      primary_key :id
      foreign_key :event_id, :events, null: false, on_delete: :cascade
      Integer :student_id, null: false
      DateTime :checked_in_at, null: false
      unique [:event_id, :student_id]
    end
  end

  down do
    drop_table(:event_check_ins)
    drop_table(:events)
  end
end
