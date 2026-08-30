# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# Represents a student on the team.

class Student < Sequel::Model
  unrestrict_primary_key
  one_to_many :lab_sessions
  one_to_many :excused_sessions
  one_to_many :event_check_ins
  many_to_many :events, join_table: :event_check_ins

  def self.get_by_id(id)
    # Try first by assuming id is the full 6-digit ID.
    student = Student[id]
    unless student
      # Try again assuming id is just the last 4 digits.
      student = Student.where(Sequel.function(:mod, :id, 10000) => id).first
    end
    return student
  end

  def project_hours
    lab_sessions.reject { |session| session.time_out.nil? || session.excluded_from_total }.inject(0) do |sum, session|
      sum + session.duration_hours
    end
  end

  def week_hours(week)
    lab_sessions.reject { |session| session.time_out.nil? }.select do |session|
      session.time_in >= week[:start] && session.time_in < week[:end]
    end.inject(0) do |sum, session|
      sum + session.duration_hours
    end
  end

  def total_sessions_attended
    lab_sessions.reject { |session| session.time_out.nil? || session.excluded_from_total }.inject(0) do |sum, session|
      sum + 1
    end
  end

  def project_seconds_between(starts_at, ends_at)
    intervals = lab_sessions.reject { |session| session.time_out.nil? || session.excluded_from_total }
                            .map { |session| [[session.time_in, starts_at].max, [session.time_out, ends_at].min] }
                            .select { |interval_start, interval_end| interval_start < interval_end }
                            .sort_by(&:first)
    merged_intervals = intervals.each_with_object([]) do |interval, merged|
      if merged.empty? || interval.first > merged.last.last
        merged << interval
      else
        merged.last[1] = [merged.last.last, interval.last].max
      end
    end
    merged_intervals.inject(0) { |total, interval| total + (interval.last - interval.first) }
  end

  def attended_timed_build?(starts_at, ends_at, current_time = Time.now.utc)
    current_time >= ends_at && project_seconds_between(starts_at, ends_at) * 3 >= (ends_at - starts_at) * 2
  end
end
