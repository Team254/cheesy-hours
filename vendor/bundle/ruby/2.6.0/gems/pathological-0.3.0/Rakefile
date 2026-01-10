require "bundler"
require "rake/testtask"

Bundler::GemHelper.install_tasks

task :test => ["test:units"]

namespace :test do
  Rake::TestTask.new(:units) do |task|
    task.libs << "test"
    task.test_files = FileList["test/unit/**/*_test.rb"]
  end
end

task :default => ["test:units"]
