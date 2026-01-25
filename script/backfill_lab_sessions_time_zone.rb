require "bundler/setup"
require "sequel"
require "active_support/time"

root = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(root) unless $LOAD_PATH.include?(root)

require "db"
require "models"
require "constants"

module BackfillLabSessionsTimeZone
  SAMPLE_LIMIT = 10

  def self.run(source_time_zone:, target_time_zone:, start_date: nil, end_date: nil,
               dry_run: true, only_date_changes: false, include_open: false, limit: nil)
    source_tz = ActiveSupport::TimeZone[source_time_zone]
    target_tz = ActiveSupport::TimeZone[target_time_zone]
    raise ArgumentError, "Unknown source time zone: #{source_time_zone}" if source_tz.nil?
    raise ArgumentError, "Unknown target time zone: #{target_time_zone}" if target_tz.nil?

    if source_tz.name == target_tz.name
      puts "Source and target time zones are the same (#{source_tz.name}); nothing to do."
      return
    end

    dataset = LabSession.dataset
    dataset = dataset.exclude(:time_out => nil) unless include_open
    if start_date
      start_date = Date.parse(start_date)
      dataset = dataset.where(Sequel.lit("DATE(time_in) >= ?", start_date))
    end
    if end_date
      end_date = Date.parse(end_date)
      dataset = dataset.where(Sequel.lit("DATE(time_in) <= ?", end_date))
    end
    dataset = dataset.order(:id)
    dataset = dataset.limit(limit.to_i) if limit

    puts "Backfilling lab_sessions from #{source_tz.name} -> #{target_tz.name}"
    puts "Dry run: #{dry_run} | only_date_changes: #{only_date_changes} | include_open: #{include_open}"
    puts "Rows in scope: #{dataset.count}"

    changed = 0
    skipped = 0
    samples = []

    dataset.each do |session|
      new_time_in = convert_time(session.time_in, source_tz, target_tz)
      new_time_out = convert_time(session.time_out, source_tz, target_tz)

      if only_date_changes && !date_changed?(session.time_in, new_time_in)
        skipped += 1
        next
      end

      if same_time?(session.time_in, new_time_in) && same_time?(session.time_out, new_time_out)
        skipped += 1
        next
      end

      changed += 1
      if samples.size < SAMPLE_LIMIT
        samples << {
          :id => session.id,
          :time_in => session.time_in,
          :new_time_in => new_time_in,
          :time_out => session.time_out,
          :new_time_out => new_time_out
        }
      end

      session.update(:time_in => new_time_in, :time_out => new_time_out) unless dry_run
    end

    puts "Changed: #{changed} | Skipped: #{skipped}"
    if samples.any?
      puts "Sample changes:"
      samples.each do |row|
        puts "  id=#{row[:id]} time_in #{row[:time_in]} -> #{row[:new_time_in]} | time_out #{row[:time_out]} -> #{row[:new_time_out]}"
      end
    end
    puts "Run again with DRY_RUN=0 to apply changes." if dry_run
  end

  def self.convert_time(value, source_tz, target_tz)
    return nil if value.nil?
    time_str = value.strftime("%Y-%m-%d %H:%M:%S")
    source_time = source_tz.parse(time_str)
    raise ArgumentError, "Failed to parse time: #{time_str}" if source_time.nil?
    source_time.in_time_zone(target_tz)
  end

  def self.same_time?(left, right)
    return left.nil? && right.nil? if left.nil? || right.nil?
    left.strftime("%Y-%m-%d %H:%M:%S") == right.strftime("%Y-%m-%d %H:%M:%S")
  end

  def self.date_changed?(left, right)
    return false if left.nil? || right.nil?
    left.strftime("%Y-%m-%d") != right.strftime("%Y-%m-%d")
  end
end

if $PROGRAM_NAME == __FILE__
  BackfillLabSessionsTimeZone.run(
    :source_time_zone => ENV["SOURCE_TIME_ZONE"] || "Etc/UTC",
    :target_time_zone => USER_TIME_ZONE,
    :start_date => ENV["START_DATE"],
    :end_date => ENV["END_DATE"],
    :dry_run => ENV["DRY_RUN"] != "0",
    :only_date_changes => ENV["ONLY_DATE_CHANGES"] == "1",
    :include_open => ENV["INCLUDE_OPEN"] == "1",
    :limit => ENV["LIMIT"]
  )
end
