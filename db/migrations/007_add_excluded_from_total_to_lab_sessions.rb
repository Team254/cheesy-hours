Sequel.migration do
  change do
    alter_table(:lab_sessions) do
      add_column :excluded_from_total, TrueClass, :null => false, :default => false
    end
  end
end
