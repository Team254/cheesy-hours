Sequel.migration do
    change do
        create_table(:optional_builds) do
            DateTime :date, null: false, unique: true
        end
    end
end