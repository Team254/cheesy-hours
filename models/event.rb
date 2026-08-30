class Event < Sequel::Model
  one_to_many :event_check_ins
  many_to_many :students, join_table: :event_check_ins

  def self.open_on(date)
    where(:date => date, :closed_at => nil).order(:id)
  end

  def open?
    closed_at.nil?
  end

  def open_on?(date)
    open? && self.date == date
  end

  def status_on(date)
    return "Closed" unless open?
    return "Scheduled" if self.date > date
    return "Open" if self.date == date
    "Ended"
  end
end
