require "bundler/setup"
require "sequel"
require "active_support/time"

root = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(root) unless $LOAD_PATH.include?(root)

require "db"
require "models"
require "constants"
require "queries"

module VerifyAttendanceLogic
  WDAY_BY_NAME = {
    "Sunday" => 0,
    "Monday" => 1,
    "Tuesday" => 2,
    "Wednesday" => 3,
    "Thursday" => 4,
    "Friday" => 5,
    "Saturday" => 6
  }.freeze

  def self.run
    tz = ActiveSupport::TimeZone[USER_TIME_ZONE]
    raise ArgumentError, "Unknown USER_TIME_ZONE: #{USER_TIME_ZONE}" if tz.nil?

    test_student_id = (ENV["TEST_STUDENT_ID"] || "99999999").to_i
    allow_existing = ENV["ALLOW_EXISTING_STUDENT"] == "1"

    base_date = Date.parse(ENV["BASE_DATE"] || "2099-01-01")
    required_wdays = REQUIRED_BUILD_DAYS.map { |day| WDAY_BY_NAME.fetch(day) }
    optional_wdays = (0..6).to_a - required_wdays

    required_date = next_date_for_wdays(base_date, required_wdays)
    optional_date = next_date_for_wdays(required_date + 1, optional_wdays)

    required_time_in = tz.parse("#{required_date} 23:30:00")
    optional_time_in = tz.parse("#{optional_date} 23:30:00")
    raise "Failed to parse required time" if required_time_in.nil?
    raise "Failed to parse optional time" if optional_time_in.nil?

    required_time_out = required_time_in + 2 * 3600
    optional_time_out = optional_time_in + 3600

    range_start = [required_date, optional_date].min - 1
    range_end = [required_date, optional_date].max + 1
    range_start_str = range_start.strftime("%Y-%m-%d")
    range_end_str = range_end.strftime("%Y-%m-%d")

    errors = []
    warnings = []

    DB.transaction(:rollback => :always) do
      if Student[test_student_id]
        if allow_existing
          warnings << "Test student id #{test_student_id} already exists; results may be polluted."
        else
          errors << "Test student id #{test_student_id} already exists. Set TEST_STUDENT_ID or ALLOW_EXISTING_STUDENT=1."
          raise Sequel::Rollback
        end
      else
        Student.create(:id => test_student_id, :first_name => "Test", :last_name => "AttendanceLogic")
      end

      required_session = LabSession.create(
        :student_id => test_student_id,
        :time_in => required_time_in,
        :time_out => required_time_out,
        :excluded_from_total => false
      )
      optional_session = LabSession.create(
        :student_id => test_student_id,
        :time_in => optional_time_in,
        :time_out => optional_time_out,
        :excluded_from_total => false
      )

      verify_stored_time(required_session, required_time_in, "required", errors)
      verify_stored_time(optional_session, optional_time_in, "optional", errors)

      summary_row = DB.fetch(
        STUDENT_ATTENDANCE_RANGE_QUERY,
        range_start_str,
        range_end_str,
        test_student_id,
        test_student_id
      ).first

      if summary_row.nil?
        errors << "STUDENT_ATTENDANCE_RANGE_QUERY returned no rows."
      else
        expected = {
          :total_attended_count => 2,
          :required_attended_count => 1,
          :required_count => 1,
          :unexcused_count => 0
        }
        expected.each do |key, value|
          actual = summary_row[key].to_i
          errors << "Expected #{key}=#{value}, got #{actual}." if actual != value
        end
      end

      build_days = DB.fetch(BUILD_DAYS_RANGE_QUERY, range_start_str, range_end_str, 0).all
      optional_flags = build_days.each_with_object({}) do |row, acc|
        acc[row[:build_date].strftime("%Y-%m-%d")] = row[:optional].to_i
      end
      required_date_key = required_date.strftime("%Y-%m-%d")
      optional_date_key = optional_date.strftime("%Y-%m-%d")

      if !optional_flags.key?(required_date_key)
        errors << "Missing required build day #{required_date_key} in BUILD_DAYS_RANGE_QUERY."
      elsif optional_flags[required_date_key] != 0
        errors << "Expected required day #{required_date_key} to be optional=0, got #{optional_flags[required_date_key]}."
      end

      if !optional_flags.key?(optional_date_key)
        errors << "Missing optional build day #{optional_date_key} in BUILD_DAYS_RANGE_QUERY."
      elsif optional_flags[optional_date_key] != 1
        errors << "Expected optional day #{optional_date_key} to be optional=1, got #{optional_flags[optional_date_key]}."
      end
    end

    puts "VerifyAttendanceLogic results"
    if errors.empty?
      puts "PASS: Attendance logic checks succeeded."
    else
      puts "FAIL: Attendance logic checks failed."
      errors.each { |error| puts "  - #{error}" }
    end
    if warnings.any?
      puts "Warnings:"
      warnings.each { |warning| puts "  - #{warning}" }
    end
    puts "Note: Changes were wrapped in a transaction and rolled back."
  end

  def self.next_date_for_wdays(start_date, wdays)
    date = start_date
    date += 1 until wdays.include?(date.wday)
    date
  end

  def self.verify_stored_time(session, expected_time, label, errors)
    stored = LabSession[session.id]
    expected_str = expected_time.strftime("%Y-%m-%d %H:%M:%S")
    stored_str = stored.time_in.strftime("%Y-%m-%d %H:%M:%S")
    if expected_str != stored_str
      errors << "Stored #{label} time_in mismatch: expected #{expected_str}, got #{stored_str}."
    end
  end
end

if $PROGRAM_NAME == __FILE__
  VerifyAttendanceLogic.run
end
