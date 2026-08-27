Sequel.migration do
  up do
    create_table(:build_schedule_batches) do
      primary_key :id
      DateTime :created_at, null: false
      Integer :created_by_bcp_id
      String :created_by_name, null: false
      DateTime :undone_at
    end

    alter_table(:scheduled_build_days) do
      add_column :starts_at, DateTime, null: true
      add_column :ends_at, DateTime, null: true
      add_column :schedule_batch_id, Integer, null: true
      add_index :schedule_batch_id
    end

    create_table(:build_schedule_batch_entries) do
      primary_key :id
      Integer :batch_id, null: false
      Date :date, null: false
      Boolean :previously_existed, null: false
      Boolean :previous_optional
      DateTime :previous_starts_at
      DateTime :previous_ends_at
      Integer :previous_schedule_batch_id
      Boolean :previous_optional_build, null: false, default: false
      Boolean :scheduled_optional, null: false
      DateTime :scheduled_starts_at, null: false
      DateTime :scheduled_ends_at, null: false
      index :batch_id
      unique [:batch_id, :date]
    end
  end

  down do
    drop_table(:build_schedule_batch_entries)

    alter_table(:scheduled_build_days) do
      drop_column :schedule_batch_id
      drop_column :ends_at
      drop_column :starts_at
    end

    drop_table(:build_schedule_batches)
  end
end
