# Copyright 2015 Team 254. All Rights Reserved.
# @author ryan@johnsonweb.us (Ryan Johnson)
#
# Represents an RFID tag

class Tag < Sequel::Model
  unrestrict_primary_key
  many_to_one :mentors
  many_to_one :students
end
