Sequel.migration do
    change do
        create_table(:optional_builds) do
            primary_key :id
            Date :date, null: false, unique: true
        end
    end
end