Sequel.migration do
  change do
    create_table(:tags) do
      primary_key :id
      String :tag_id, :null => false, :unique => true
      Integer :student_id, :null => true
      Integer :mentor_id, :null => true
    end
  end
end
