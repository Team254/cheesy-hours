# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Represents a single time range spent in the lab by a student.

class LabSession < Sequel::Model
  many_to_one :student
  many_to_one :mentor
end
