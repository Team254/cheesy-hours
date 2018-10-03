Sequel.migration do
  change do
    create_table(:mentors) do
      primary_key :id
      String :first_name, :null => false
      String :last_name, :null => false
      String :phone_number
    end
  end
end
