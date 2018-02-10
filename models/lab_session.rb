# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Represents a single time range spent in the lab by a student.

class LabSession < Sequel::Model
  many_to_one :student
  many_to_one :mentor

  def duration_hours
    0
    # time_out.nil? ? 0 : (time_out - time_in) / 3600
  end
end
