# Copyright 2021 Team 254. All Rights Reserved.
# @author pat@team254.com (Patrick Fairbank)
#
# Represents a lab checkin by a mentor (for contact tracing).

class MentorCheckin < Sequel::Model
  many_to_one :mentor
end
