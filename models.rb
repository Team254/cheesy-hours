# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Sets up database connection and includes all the models for convenience.

require "sequel"

require "db"
require "models/lab_session"
require "models/mentor"
require "models/mentor_checkin"
require "models/optional_build"
require "models/student"
require "models/excused_session"
require "models/scheduled_build_day"