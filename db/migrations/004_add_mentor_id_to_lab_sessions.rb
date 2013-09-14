Sequel.migration do
  change do
    alter_table(:lab_sessions) do
      add_column :mentor_id, Integer
    end
  end
end
