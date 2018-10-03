Sequel.migration do
  change do
    alter_table(:lab_sessions) do
      add_column :notes, :text
      add_column :mentor_name, String
    end
  end
end
