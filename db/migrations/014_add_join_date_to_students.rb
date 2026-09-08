Sequel.migration do
  up do
    alter_table(:students) do
      add_column :join_date, Date
    end
  end

  down do
    alter_table(:students) do
      drop_column :join_date
    end
  end
end
