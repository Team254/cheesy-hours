Sequel.migration do
    change do
        create_table(:excused_sessions) do
            DateTime :date, null: false
            Integer :student_id, null: false
        end

        # workaround since ActiveRecord doesn't support multiple primary keys
        execute "ALTER TABLE cheesy_frc_hours.excused_sessions ADD PRIMARY KEY (date, student_id);"
    end
end