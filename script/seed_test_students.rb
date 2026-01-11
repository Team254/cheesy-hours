require "bundler/setup"
require "sequel"

root = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(root) unless $LOAD_PATH.include?(root)

require "db"
require "models"

module SeedTestStudents
  def self.run(count:, start_id:)
    ids = ((start_id + 1)..(start_id + count)).to_a
    existing_ids = Student.where(:id => ids).select_map(:id)
    missing_ids = ids - existing_ids

    missing_ids.each do |student_id|
      Student.create(
        :id => student_id,
        :first_name => "Test",
        :last_name => format("Student%02d", student_id - start_id)
      )
    end

    puts "Ensured #{ids.size} test students in ID range #{ids.first}-#{ids.last}."
  end
end

if $PROGRAM_NAME == __FILE__
  count = (ENV["COUNT"] || "30").to_i
  start_id = (ENV["START_ID"] || "900000").to_i
  SeedTestStudents.run(count: count, start_id: start_id)
end
