Sequel.migration do
  change do
    create_table(:lab_sessions) do
      primary_key :id
      Integer :student_id, :null => false
      DateTime :time_in, :null => false
      DateTime :time_out
    end
  end
end
