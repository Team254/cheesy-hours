# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Represents a student on the team.

class Student < Sequel::Model
  unrestrict_primary_key
  one_to_many :lab_sessions

  def project_hours
    lab_sessions.reject { |session| session.time_out.nil? }.inject(0) do |sum, session|
      sum + (session.time_out - session.time_in) / 3600
    end
  end
end
