class EventExcusal < Sequel::Model
  many_to_one :event
  many_to_one :student
end
