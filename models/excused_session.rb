class ExcusedSession < Sequel::Model
    unrestrict_primary_key
    many_to_one :student
end