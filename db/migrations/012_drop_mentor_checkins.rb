Sequel.migration do
  up do
    drop_table(:mentor_checkins)
  end

  down do
    create_table(:mentor_checkins) do
      primary_key :id
      Integer :mentor_id, :null => false
      DateTime :time_in, :null => false
    end
  end
end
