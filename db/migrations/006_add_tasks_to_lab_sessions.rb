Sequel.migration do
  change do
    alter_table(:lab_sessions) do
      add_column :tasks, :text
    end
  end
end
