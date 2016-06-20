# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Script for starting/stopping the hours server.

require "bundler/setup"
require "daemons"
require "pathological"
require "thin"

Daemons.run_proc("hours_server", :monitor => true) do
  require "hours_server"

  Thin::Server.start("0.0.0.0", Config.port, CheesyHours::Server)
end
