class ExcusedSession < Sequel::Model
    unrestrict_primary_key
    many_to_one :student

    def validate
        super
        errors.add(:date, 'cannot be blank') if !date
        errors.add(:student_id, 'cannot be blank') if !student_id
    end 

end