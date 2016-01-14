# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Contains maintenance and deployment configuration.

require "bundler/setup"
require "fezzik"
require "pathological"
require "sequel"

Sequel.extension :migration

# Task for executing any pending database schema changes.
namespace :db do
  task :migrate do
    require "db"
    Sequel::Migrator.run(DB, "db/migrations")
  end
end

include Fezzik::DSL
Fezzik.init(:tasks => "config/tasks")

set :app, "cheesy-frc-hours"
set :deploy_to, "/opt/team254/#{app}"
set :release_path, "#{deploy_to}/releases/#{Time.now.strftime("%Y%m%d%H%M")}"
set :local_path, Dir.pwd
set :user, "team254"

Fezzik.destination :prod do
  # Fill in parameters for deployment host, database and e-mail account here.
  set :domain, "#{user}@frc-hours.team254.com"
  env :port, 9006
  env :db_host, "localhost"
  env :db_user, "team254"
  env :db_password, "complementingnotmixing"
  env :db_database, "cheesy_frc_hours"
  env :wordpress_auth_url, "http://www.team254.com/auth/"
  env :base_address, "http://frc-hours.team254.com"
end