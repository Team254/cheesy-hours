# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Sets up database connection.

require_relative "hours_config"

DB = Sequel.mysql2({ :host => CheesyHours::Config.db_host, :user => CheesyHours::Config.db_user,
	:password => CheesyHours::Config.db_password, :database => CheesyHours::Config.db_database })
