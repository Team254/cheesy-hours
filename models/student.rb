# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Represents a student on the team.

class Student < Sequel::Model
  unrestrict_primary_key
  one_to_many :lab_sessions

  def self.get_by_id(id)
    # Try first by assuming id is the full 6-digit ID.
    student = Student[id]
    unless student
      # Try again assuming id is just the last 4 digits.
      student = Student.where(Sequel.function(:mod, :id, 10000) => id).first
    end
    return student
  end

  def project_hours
    lab_sessions.reject { |session| session.time_out.nil? }.inject(0) do |sum, session|
      sum + session.duration_hours
    end
  end

  def week_hours(week)
    lab_sessions.reject { |session| session.time_out.nil? }.select do |session|
      session.time_in >= week[:start] && session.time_in < week[:end]
    end.inject(0) do |sum, session|
      sum + session.duration_hours
    end
  end

  def total_sessions_attended
    lab_sessions.reject { |session| session.time_out.nil? }.inject(0) do |sum, session|
      sum + 1
    end
  end
end
