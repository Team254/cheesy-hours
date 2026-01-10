Sequel.migration do
    change do
        create_table(:scheduled_build_days) do
            primary_key :id
            Date :date, null: false, unique: true
            Boolean :optional, null: false, default: false
        end
    end
end
