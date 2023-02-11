Sequel.migration do
    change do
        create_table(:excused_sessions) do
            primary_key :id
            Date :date, null: false
            Integer :student_id, null: false
        end
    end
end