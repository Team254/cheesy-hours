# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Represents a mentor on the team with the ability to sign out students.

class Mentor < Sequel::Model
  one_to_many :lab_sessions
end
