# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Represents a student on the team.

class Student < Sequel::Model
  unrestrict_primary_key
  one_to_many :lab_sessions
end
