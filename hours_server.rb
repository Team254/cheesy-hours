# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# The main class of the hours web server.

require "active_support/time"
require "cgi"
require "cheesy-common"
require "digest"
require "pathological"
require "securerandom"
require "sinatra/base"
require "json"

require "models"
require "constants"
require "queries"

module CheesyHours
  class Server < Sinatra::Base
    RESET_ACTIVITY_TABLES = {
      :lab_sessions => ["Lab sessions", :time_in, :datetime],
      :excused_sessions => ["Excusals", :date, :date],
      :optional_builds => ["Optional builds", :date, :date],
      :scheduled_build_days => ["Scheduled builds", :date, :date],
      :build_schedule_batch_entries => ["Schedule batch entries", :date, :date]
    }.freeze
    DevUser = Struct.new(:name_display, :bcp_id) do
      def has_permission?(_permission)
        true
      end
    end
    use Rack::Session::Cookie, :key => "rack.session", :expire_after => 3600

    helpers do
      def user_time_zone
        @user_time_zone ||= ActiveSupport::TimeZone[USER_TIME_ZONE]
      end

      def parse_user_time(value)
        value = value.to_s
        raise ArgumentError, "Missing time" if value.strip.empty?
        time = user_time_zone.parse(value)
        raise ArgumentError, "Invalid time" if time.nil?
        time.utc
      end

      def safe_referrer(fallback = "/")
        ref = params[:referrer].to_s.gsub("\\", "/")
        ref.start_with?("/") && !ref.start_with?("//") ? ref : fallback
      end

      def parse_build_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        halt(400, "Invalid date.")
      end

      def parse_build_hour(value)
        Integer(value.to_s, 10)
      rescue ArgumentError
        halt(400, "Invalid build hour.")
      end

      def build_time_on(build_date, hour)
        user_time_zone.local(build_date.year, build_date.month, build_date.day, hour).utc
      end

      def parse_reset_cutoff(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        halt(400, "Invalid reset cutoff date.")
      end

      def reset_cutoff_time(cutoff_date)
        user_time_zone.local(cutoff_date.year, cutoff_date.month, cutoff_date.day).utc
      end

      def reset_activity_datasets(cutoff_date)
        cutoff_time = reset_cutoff_time(cutoff_date)
        RESET_ACTIVITY_TABLES.each_with_object({}) do |(table, (_label, column, type)), datasets|
          cutoff = type == :datetime ? cutoff_time : cutoff_date
          datasets[table] = DB[table].where(Sequel[column] < cutoff)
        end
      end

      def reset_activity_preview(cutoff_date)
        cutoff_time = reset_cutoff_time(cutoff_date)
        datasets = reset_activity_datasets(cutoff_date)
        candidate_batch_ids = datasets[:build_schedule_batch_entries]
                              .exclude(:batch_id => nil)
                              .select_map(:batch_id)
                              .uniq
        remaining_batch_ids = DB[:build_schedule_batch_entries]
                              .where(Sequel[:date] >= cutoff_date)
                              .exclude(:batch_id => nil)
                              .select_map(:batch_id)
                              .uniq
        batch_ids_to_delete = candidate_batch_ids - remaining_batch_ids
        batch_delete_count = batch_ids_to_delete.empty? ? 0 : DB[:build_schedule_batches].where(:id => batch_ids_to_delete).count
        rows = RESET_ACTIVITY_TABLES.map do |table, (label, _column, _type)|
          delete_count = datasets[table].count
          remaining_count = DB[table].count - delete_count
          {
            :table => table,
            :label => label,
            :delete_count => delete_count,
            :remaining_count => remaining_count
          }
        end
        remaining_batch_count = DB[:build_schedule_batches].count - batch_delete_count
        rows << {
          :table => :build_schedule_batches,
          :label => "Schedule batches",
          :delete_count => batch_delete_count,
          :remaining_count => remaining_batch_count
        }
        project_seconds = DB.fetch(
          "SELECT COALESCE(SUM(TIMESTAMPDIFF(SECOND, time_in, time_out)), 0) AS seconds FROM lab_sessions WHERE time_in < ? AND time_out IS NOT NULL",
          cutoff_time
        ).get(:seconds).to_f
        crossing_sessions = DB[:lab_sessions]
                            .where(Sequel[:time_in] < cutoff_time)
                            .where(Sequel.|({ :time_out => nil }, Sequel[:time_out] > cutoff_time))
                            .count
        {
          :cutoff_date => cutoff_date,
          :cutoff_time => cutoff_time,
          :datasets => datasets,
          :batch_ids_to_delete => batch_ids_to_delete,
          :rows => rows,
          :project_hours => project_seconds / 3600,
          :crossing_sessions => crossing_sessions
        }
      end

      def reset_preview_signature(preview)
        {
          "cutoff_date" => preview[:cutoff_date].iso8601,
          "delete_counts" => preview[:rows].each_with_object({}) do |row, counts|
            counts[row[:table].to_s] = row[:delete_count]
          end,
          "delete_fingerprints" => preview[:datasets].each_with_object({}) do |(table, dataset), fingerprints|
            fingerprints[table.to_s] = Digest::SHA256.hexdigest(dataset.select_map(:id).sort.join(","))
          end.merge(
            "build_schedule_batches" => Digest::SHA256.hexdigest(preview[:batch_ids_to_delete].sort.join(","))
          ),
          "crossing_sessions" => preview[:crossing_sessions]
        }
      end

      def reindex_students_program
        CheesyCommon::Config.program
      rescue CheesyCommon::Config::NoValueFoundError
        nil
      end

      def reindex_students_preview
        program = reindex_students_program
        members_students = CheesyCommon::Auth.find_users_with_permission("EVENTS_SIGNUP_EVENT", program: program).map do |student|
          name = Array(student.name)
          {
            :id => Integer(student.bcp_id.to_s, 10),
            :first_name => name[1].to_s,
            :last_name => name[0].to_s
          }
        rescue ArgumentError
          halt(409, "Members returned a student with an invalid ID.")
        end
        duplicate_ids = members_students.group_by { |student| student[:id] }
                                        .select { |_id, students| students.length > 1 }
                                        .keys
        halt(409, "Members returned duplicate student IDs: #{duplicate_ids.sort.join(', ')}.") unless duplicate_ids.empty?
        if members_students.any? { |student| student[:first_name].empty? || student[:last_name].empty? }
          halt(409, "Members returned a student with a missing first or last name.")
        end

        members_students.sort_by! { |student| student[:id] }
        database_students = Student.order(:id).all.map do |student|
          { :id => student.id, :first_name => student.first_name, :last_name => student.last_name }
        end
        members_by_id = members_students.each_with_object({}) { |student, rows| rows[student[:id]] = student }
        database_by_id = database_students.each_with_object({}) { |student, rows| rows[student[:id]] = student }
        added_students = (members_by_id.keys - database_by_id.keys).sort.map { |id| members_by_id[id] }
        removed_students = (database_by_id.keys - members_by_id.keys).sort.map { |id| database_by_id[id] }
        updated_students = (members_by_id.keys & database_by_id.keys).sort.each_with_object([]) do |id, updates|
          members_student = members_by_id[id]
          database_student = database_by_id[id]
          next if members_student[:first_name] == database_student[:first_name] &&
                  members_student[:last_name] == database_student[:last_name]

          updates << { :current => database_student, :replacement => members_student }
        end

        {
          :program => program,
          :members_students => members_students,
          :database_students => database_students,
          :added_students => added_students,
          :updated_students => updated_students,
          :removed_students => removed_students,
          :unchanged_count => members_students.length - added_students.length - updated_students.length,
          :blocked => members_students.empty?
        }
      end

      def student_roster_fingerprint(students)
        Digest::SHA256.hexdigest(JSON.generate(students.map do |student|
          [student[:id], student[:first_name], student[:last_name]]
        end))
      end

      def reindex_students_preview_signature(preview)
        {
          "program" => preview[:program].to_s,
          "members_count" => preview[:members_students].length,
          "database_count" => preview[:database_students].length,
          "members_fingerprint" => student_roster_fingerprint(preview[:members_students]),
          "database_fingerprint" => student_roster_fingerprint(preview[:database_students])
        }
      end
    end
    # Enforce authentication for all non-public routes.
    before do
      if ENV["DISABLE_AUTH"] == "1"
        dev_bcp_id = (ENV["HOURS_BYPASS_BCP_ID"] || "900001").to_i
        @user = DevUser.new("Dev User", dev_bcp_id)
        session[:user] = @user
      elsif ENV["HOURS_BYPASS_AUTH"] == "1"
        # Local dev bypass for Team 254 SSO.
        dev_bcp_id = (ENV["HOURS_BYPASS_BCP_ID"] || "900001").to_i
        @user = CheesyCommon::User.new(
          "name_display" => "Dev User",
          "bcp_id" => dev_bcp_id,
          "permissions" => ["HOURS_SIGN_IN", "HOURS_VIEW", "HOURS_EDIT", "HOURS_DELETE", "HOURS_VIEW_REPORT", "DATABASE_ADMIN"]
        )
        session[:user] = @user
      else
        @user = CheesyCommon::Auth.get_user(request)
        if @user.nil?
          session[:user] = nil
          # Note: signin_internal blocks all outside sources (localhost only)
          unless ["/", "/sms", "/signin_internal", "/signout_automatic"].include?(request.path)
            redirect "#{CheesyCommon::Config.members_url}?site=hours&path=#{request.path}"
          end
        else
          session[:user] = @user
        end
      end
    end

    get "/logout" do
      session[:user] = nil
      redirect "#{CheesyCommon::Config.members_url}/logout"
    end

    get "/" do
      @signed_in_sessions = LabSession.where(:time_out => nil)
      erb :index
    end

    post "/signin" do
      halt(403, "Insufficient permissions. If you're a student, please sign in on Events.") unless @user.has_permission?("HOURS_SIGN_IN")

      @student = Student.get_by_id(params[:student_id])
      halt(400, "Invalid student.") if @student.nil?

      # Restrict sign-ins to the lab's IP address ranges.
      ip_whitelist = CheesyCommon::Config.signin_ip_whitelist
      real_ip = request.env["HTTP_X_REAL_IP"].to_s
      if !ip_whitelist.empty? && (real_ip.empty? || ip_whitelist.none? { |ip| real_ip.start_with?(ip) })
        halt(400, "Invalid IP address. Must sign in from the Robotics Lab.")
      end

      # Check for existing open lab sessions.
      unless LabSession.where(:student_id => @student.id, :time_out => nil).empty?
        halt(400, "An open lab session already exists for student #{@student.id}.")
      end
      @student.add_lab_session(:time_in => Time.now.utc)

      # Add an optional build to the database if necessary.
      # (If today is not mandatory and the optional build is not in the database)
      currentUserTime = user_time_zone.now
      if !REQUIRED_BUILD_DAYS.include?(currentUserTime.strftime("%A")) &&
          OptionalBuild.where(:date => currentUserTime.strftime("%Y-%m-%d")).empty? &&
          ScheduledBuildDay.where(:date => currentUserTime.strftime("%Y-%m-%d")).empty?
        OptionalBuild.create(:date => currentUserTime.strftime("%Y-%m-%d"))
      end

      redirect "/"
    end

    post "/signin_internal" do
      @student = Student.get_by_id(params[:student_id])
      halt(400, "Invalid student.") if @student.nil?

      # Check for existing open lab sessions.
      unless LabSession.where(:student_id => @student.id, :time_out => nil).empty?
        halt(400, "An open lab session already exists for student #{@student.id}.")
      end
      @student.add_lab_session(:time_in => Time.now.utc)

      "Success"
    end

    get "/leader_board" do
      erb :leader_board
    end

    get "/calendar" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_VIEW")
      today = user_time_zone.now.to_date
      requested_semester = params[:semester].to_s.downcase
      @semester = %w[fall spring summer].include?(requested_semester) ? requested_semester : case today.month
                                                                                            when 1..5 then "spring"
                                                                                            when 6..7 then "summer"
                                                                                            else "fall"
                                                                                            end
      requested_year = params[:year].to_i
      @semester_year = requested_year > 0 ? requested_year : today.year
      @hide_optional = ["1", "true", "on"].include?(params[:hide_optional].to_s)

      case @semester
      when "fall"
        @semester_start = Date.new(@semester_year, 8, 1)
        @semester_end = Date.new(@semester_year, 12, 31)
      when "spring"
        @semester_start = Date.new(@semester_year, 1, 1)
        @semester_end = Date.new(@semester_year, 5, 31)
      else
        @semester_start = Date.new(@semester_year, 6, 1)
        @semester_end = Date.new(@semester_year, 7, 31)
      end
      erb :calendar
    end

    get "/at_risk_students" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")

      today = user_time_zone.now.to_date
      requested_semester = params[:semester].to_s.downcase
      @semester = %w[fall spring summer].include?(requested_semester) ? requested_semester : case today.month
                                                                                            when 1..5 then "spring"
                                                                                            when 6..7 then "summer"
                                                                                            else "fall"
                                                                                            end
      requested_year = params[:year].to_i
      @semester_year = requested_year > 0 ? requested_year : today.year

      case @semester
      when "fall"
        @semester_start = Date.new(@semester_year, 8, 1)
        @semester_end = Date.new(@semester_year, 12, 31)
      when "spring"
        @semester_start = Date.new(@semester_year, 1, 1)
        @semester_end = Date.new(@semester_year, 5, 31)
      else
        @semester_start = Date.new(@semester_year, 6, 1)
        @semester_end = Date.new(@semester_year, 7, 31)
      end

      @total_absence_limit = 5
      @consecutive_absence_limit = 3
      students_by_id = Student.all.each_with_object({}) { |student, students| students[student.id] = student }
      DB.fetch "SET sql_mode=(SELECT REPLACE(@@sql_mode,'ONLY_FULL_GROUP_BY',''));" do end
      attendance_rows = DB.fetch(
        CALENDAR_BUILD_INFO_RANGE_QUERY,
        @semester_start.strftime("%Y-%m-%d"),
        @semester_end.strftime("%Y-%m-%d"),
        1
      ).all

      @at_risk_students = attendance_rows.group_by { |row| row[:student_id] }.map do |student_id, rows|
        student = students_by_id[student_id]
        next if student.nil?

        absence_dates = []
        longest_streak = 0
        longest_streak_start = nil
        longest_streak_end = nil
        current_streak = 0
        current_streak_start = nil

        rows.sort_by { |row| row[:build_date] }.each do |row|
          next unless row[:build_date] <= today && row[:finalized] == 1 && row[:required] == 1

          if row[:attended] == 0 && row[:excused] == 0
            absence_dates << row[:build_date]
            current_streak_start ||= row[:build_date]
            current_streak += 1
            if current_streak > longest_streak
              longest_streak = current_streak
              longest_streak_start = current_streak_start
              longest_streak_end = row[:build_date]
            end
          else
            current_streak = 0
            current_streak_start = nil
          end
        end

        total_absences = absence_dates.length
        next unless total_absences >= 3 || longest_streak >= 3

        status = if total_absences > @total_absence_limit || longest_streak > @consecutive_absence_limit
                   :over_limit
                 elsif total_absences == @total_absence_limit || longest_streak == @consecutive_absence_limit
                   :at_limit
                 else
                   :at_risk
                 end
        {
          :student => student,
          :total_absences => total_absences,
          :longest_streak => longest_streak,
          :longest_streak_start => longest_streak_start,
          :longest_streak_end => longest_streak_end,
          :most_recent_absence => absence_dates.last,
          :status => status
        }
      end.compact
      status_order = { :over_limit => 0, :at_limit => 1, :at_risk => 2 }
      @at_risk_students.sort_by! do |row|
        [status_order[row[:status]], -row[:total_absences], -row[:longest_streak], row[:student].last_name, row[:student].first_name]
      end

      erb :at_risk_students
    end

    get "/optionalize_past_offdays" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @referrer = request.referrer
      erb :optionalize_past_offdays
    end

    post "/optionalize_past_offdays" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")

      DB.fetch BUILD_DAYS_QUERY do |row|
        if !REQUIRED_BUILD_DAYS.include?(row[:build_date].strftime("%A"))
          OptionalBuild.create(:date => row[:build_date]) rescue nil
        end
      end

      redirect safe_referrer
    end

    get "/build_schedule" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")

      today = user_time_zone.now.to_date
      @upcoming_builds = ScheduledBuildDay.where(Sequel[:date] >= today).order(:date).all
      @edit_date = params[:date].to_s.empty? ? nil : parse_build_date(params[:date])
      @edit_build = @edit_date.nil? ? nil : ScheduledBuildDay.where(:date => @edit_date).first
      @edit_optional = @edit_build ? @edit_build.optional : ["1", "true"].include?(params[:optional].to_s)
      @schedule_batches = DB[:build_schedule_batches].order(Sequel.desc(:created_at)).all
      batch_ids = @schedule_batches.map { |batch| batch[:id] }
      @schedule_batch_entries = if batch_ids.empty?
                                  {}
                                else
                                  DB[:build_schedule_batch_entries].where(:batch_id => batch_ids).order(:date).all.group_by { |entry| entry[:batch_id] }
                                end
      erb :build_schedule
    end

    post "/build_schedule" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")

      start_hour = parse_build_hour(params[:start_hour])
      end_hour = parse_build_hour(params[:end_hour])
      halt(400, "Build start must be a full hour from midnight through 10 PM.") unless (0..22).include?(start_hour)
      halt(400, "Build end must be a full hour from 1 AM through 11 PM.") unless (1..23).include?(end_hour)
      halt(400, "Build end must be after build start.") unless end_hour > start_hour

      build_dates = if params[:schedule_mode] == "repeating"
                      range_start = parse_build_date(params[:range_start])
                      range_end = parse_build_date(params[:range_end])
                      halt(400, "Schedule end must not precede its start.") if range_end < range_start
                      halt(400, "Schedule range cannot exceed two years.") if (range_end - range_start).to_i > 730
                      weekdays = Array(params[:weekdays]).map { |weekday| Integer(weekday, 10) rescue -1 }.uniq
                      halt(400, "Select at least one weekday.") if weekdays.empty? || weekdays.any? { |weekday| !(0..6).include?(weekday) }
                      (range_start..range_end).select { |date| weekdays.include?(date.wday) }
                    else
                      [parse_build_date(params[:date])]
                    end
      halt(400, "No build dates matched this schedule.") if build_dates.empty?

      optional = ["1", "true"].include?(params[:optional].to_s)
      replace_existing = params[:replace_existing] == "1"
      created_count = 0
      updated_count = 0
      skipped_count = 0
      batch_id = nil

      DB.transaction do
        if params[:schedule_mode] == "repeating"
          batch_id = DB[:build_schedule_batches].insert(
            :created_at => Time.now.utc,
            :created_by_bcp_id => @user.bcp_id,
            :created_by_name => @user.name_display
          )
        end

        build_dates.each do |build_date|
          starts_at = build_time_on(build_date, start_hour)
          ends_at = build_time_on(build_date, end_hour)
          scheduled_build = ScheduledBuildDay.where(:date => build_date).first

          if scheduled_build && !replace_existing
            skipped_count += 1
            next
          end

          previous_values = if scheduled_build
                              {
                                :previously_existed => true,
                                :previous_optional => scheduled_build.optional,
                                :previous_starts_at => scheduled_build.starts_at,
                                :previous_ends_at => scheduled_build.ends_at,
                                :previous_schedule_batch_id => scheduled_build.schedule_batch_id
                              }
                            else
                              {
                                :previously_existed => false,
                                :previous_optional => nil,
                                :previous_starts_at => nil,
                                :previous_ends_at => nil,
                                :previous_schedule_batch_id => nil
                              }
                            end
          previous_optional_build = !OptionalBuild.where(:date => build_date).empty?

          if scheduled_build
            scheduled_build.update(:optional => optional, :starts_at => starts_at, :ends_at => ends_at, :schedule_batch_id => batch_id)
            updated_count += 1
          else
            ScheduledBuildDay.dataset.insert(
              :date => build_date,
              :optional => optional,
              :starts_at => starts_at,
              :ends_at => ends_at,
              :schedule_batch_id => batch_id
            )
            created_count += 1
          end

          if batch_id
            DB[:build_schedule_batch_entries].insert(
              previous_values.merge(
                :batch_id => batch_id,
                :date => build_date,
                :previous_optional_build => previous_optional_build,
                :scheduled_optional => optional,
                :scheduled_starts_at => starts_at,
                :scheduled_ends_at => ends_at
              )
            )
          end
          OptionalBuild.where(:date => build_date).delete
        end

        if batch_id && created_count + updated_count == 0
          DB[:build_schedule_batches].where(:id => batch_id).delete
          batch_id = nil
        end
      end

      redirect "/build_schedule?created=#{created_count}&updated=#{updated_count}&skipped=#{skipped_count}&batch_id=#{batch_id}"
    end

    post "/build_schedule/:date/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")

      scheduled_build = ScheduledBuildDay.where(:date => parse_build_date(params[:date])).first
      halt(400, "Scheduled build not found.") if scheduled_build.nil?
      scheduled_build.delete
      redirect "/build_schedule?deleted=1"
    end

    post "/build_schedule/delete_selected" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")

      build_dates = Array(params[:dates]).map { |date| parse_build_date(date) }.uniq
      halt(400, "Select at least one build to remove.") if build_dates.empty?

      deleted_count = ScheduledBuildDay.where(:date => build_dates).delete
      redirect "/build_schedule?deleted=#{deleted_count}"
    end

    post "/build_schedule/batches/:id/undo" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")

      batch_id = Integer(params[:id], 10) rescue nil
      halt(400, "Invalid scheduling batch.") if batch_id.nil?
      batch = DB[:build_schedule_batches].where(:id => batch_id).first
      halt(400, "Scheduling batch not found.") if batch.nil?
      halt(400, "Scheduling batch has already been undone.") unless batch[:undone_at].nil?

      entries = DB[:build_schedule_batch_entries].where(:batch_id => batch_id).order(:date).all
      removed_count = 0
      restored_count = 0
      skipped_count = 0

      DB.transaction do
        entries.each do |entry|
          scheduled_build = ScheduledBuildDay.where(:date => entry[:date]).first
          if scheduled_build.nil? || scheduled_build.schedule_batch_id != batch_id
            skipped_count += 1
            next
          end

          if entry[:previously_existed]
            scheduled_build.update(
              :optional => entry[:previous_optional],
              :starts_at => entry[:previous_starts_at],
              :ends_at => entry[:previous_ends_at],
              :schedule_batch_id => entry[:previous_schedule_batch_id]
            )
            restored_count += 1
          else
            scheduled_build.delete
            removed_count += 1
          end

          if entry[:previous_optional_build] && OptionalBuild.where(:date => entry[:date]).empty?
            OptionalBuild.create(:date => entry[:date])
          end
        end
        DB[:build_schedule_batches].where(:id => batch_id).update(:undone_at => Time.now.utc)
      end

      redirect "/build_schedule?batch_removed=#{removed_count}&batch_restored=#{restored_count}&batch_skipped=#{skipped_count}"
    end

    get "/schedule_optional" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @referrer = request.referrer
      @date = params[:date]
      erb :optional_build_scheduler
    end

    post "/schedule_optional" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      halt(400, "Invalid date.") if params[:date].nil?|| params[:date] == ""

      date = params[:date]
      scheduled_build_day = ScheduledBuildDay.where(:date => date).first
      if scheduled_build_day
        scheduled_build_day.update(:optional => true, :schedule_batch_id => nil)
      else
        ScheduledBuildDay.create(:date => date, :optional => true)
      end
      OptionalBuild.where(:date => date).delete

      redirect safe_referrer
    end

    get "/delete_optional/:date" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @referrer = request.referrer

      erb :delete_optional_build
    end

    post "/delete_optional/:date" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      date = params[:date]
      OptionalBuild.where(:date => date).delete
      scheduled_build_day = ScheduledBuildDay.where(:date => date).first
      if scheduled_build_day
        scheduled_build_day.update(:optional => false, :schedule_batch_id => nil)
      else
        ScheduledBuildDay.create(:date => date, :optional => false)
      end

      redirect safe_referrer
    end

    get "/build_days/:date/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("DATABASE_ADMIN")
      @referrer = request.referrer
      @date = params[:date]
      erb :delete_build_day
    end

    post "/build_days/:date/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("DATABASE_ADMIN")
      date = params[:date]
      halt(400, "Invalid date.") if date.nil? || date == ""

      OptionalBuild.where(:date => date).delete
      ScheduledBuildDay.where(:date => date).delete
      ExcusedSession.where(:date => date).delete
      LabSession.where(Sequel.lit("#{utc_to_local_date('time_in')} = ?", date)).update(:excluded_from_total => true)

      redirect safe_referrer
    end
    get "/schedule_build_day" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @referrer = request.referrer
      @date = params[:date]
      erb :schedule_build_day
    end

    post "/schedule_build_day" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      halt(400, "Invalid date.") if params[:date].nil? || params[:date] == ""
      halt(400, "Invalid optional value.") if params[:optional].nil?

      optional = params[:optional] == "1" || params[:optional] == "true"
      date = params[:date]
      updated = ScheduledBuildDay.where(:date => date).update(:optional => optional, :schedule_batch_id => nil)
      ScheduledBuildDay.create(:date => date, :optional => optional) if updated == 0
      OptionalBuild.where(:date => date).delete

      redirect safe_referrer
    end

    get "/my_attendance" do
      halt(403, "You must be logged in.") if @user.nil?
      @student = Student[@user.bcp_id]
      halt(400, "Student record not found. Please contact an administrator.") if @student.nil?
      
      today = user_time_zone.now.to_date
      requested_semester = params[:semester].to_s.downcase
      @semester = %w[fall spring summer].include?(requested_semester) ? requested_semester : case today.month
                                                                                            when 1..5 then "spring"
                                                                                            when 6..7 then "summer"
                                                                                            else "fall"
                                                                                            end
      requested_year = params[:year].to_i
      @semester_year = requested_year > 0 ? requested_year : today.year

      case @semester
      when "fall"
        @semester_start = Date.new(@semester_year, 8, 1)
        @semester_end = Date.new(@semester_year, 12, 31)
      when "spring"
        @semester_start = Date.new(@semester_year, 1, 1)
        @semester_end = Date.new(@semester_year, 5, 31)
      else
        @semester_start = Date.new(@semester_year, 6, 1)
        @semester_end = Date.new(@semester_year, 7, 31)
      end
      
      erb :my_attendance
    end
    get "/students/:id" do
      @student = Student[params[:id]]
      halt(400, "Invalid student.") if @student.nil?
      erb :student
    end

    get "/students/:id/mark_excused" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @student = Student[params[:id]]
      halt(400, "Invalid student.") if @student.nil?
      @referrer = request.referrer
      if !params[:date].nil?
        @date = params[:date]
      end
      erb :mark_excused
    end

    post "/students/:id/mark_excused" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      halt(400, "Missing date.") if params[:date].nil? || params[:date] == ""
      ExcusedSession.create(:date => params[:date], :student_id => params[:id])
      redirect safe_referrer
    end

    get "/students/:id/excusals/:date/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @excusal = ExcusedSession.where(:date => params[:date], :student_id => params[:id]).first
      halt(400, "Invalid excusal.") if @excusal.nil?
      @referrer = request.referrer
      erb :delete_excusal
    end

    post "/students/:id/excusals/:date/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @excusal = ExcusedSession.where(:date => params[:date], :student_id => params[:id]).first
      halt(400, "Invalid excusal.") if @excusal.nil?
      @excusal.delete
      redirect safe_referrer
    end

    get "/students/:id/new_lab_session" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @student = Student[params[:id]]
      halt(400, "Invalid student.") if @student.nil?
      @referrer = request.referrer
      if !params[:date].nil?
        # allow prefilling the date based on a url parameter
        @lab_session = OpenStruct.new(:time_in => params[:date], :time_out => params[:date])
      end
      erb :edit_lab_session
    end

    post "/students/:id/new_lab_session" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      student = Student[params[:id]]
      halt(400, "Invalid student.") if student.nil?
      student.add_lab_session(:time_in => parse_user_time(params[:time_in]),
                              :time_out => params[:time_out].to_s.empty? ? nil : parse_user_time(params[:time_out]),
                              :notes => params[:notes],
                              :mentor_name => params[:time_out].to_s.empty? ? nil : @user.name_display)
      redirect safe_referrer("/leader_board")
    end

    get "/lab_sessions/:id/edit" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @referrer = request.referrer
      erb :edit_lab_session
    end

    post "/lab_sessions/:id/edit" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      if !params[:time_out].to_s.empty? && @lab_session.time_out.nil?
        mentor_name = @user.name_display
      elsif params[:time_out].to_s.empty? && @lab_session.time_out
        mentor_name = nil
      else
        mentor_name = @lab_session.mentor_name
      end
      @lab_session.update(
        :time_in => parse_user_time(params[:time_in]),
        :time_out => params[:time_out].to_s.empty? ? nil : parse_user_time(params[:time_out]),
        :notes => params[:notes],
        :mentor_name => mentor_name,
        :excluded_from_total => params[:excluded_from_total] == "on"
      )
      redirect safe_referrer("/leader_board")
    end

    get "/lab_sessions/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_DELETE")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @referrer = request.referrer
      erb :delete_lab_session
    end

    post "/lab_sessions/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_DELETE")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @lab_session.delete
      redirect safe_referrer("/leader_board")
    end

    get "/lab_sessions/:id/sign_out" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_VIEW")
      lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if lab_session.nil?
      lab_session.update(:time_out => Time.now.utc, :mentor_name => @user.name_display)
      redirect "/"
    end

    get "/lab_sessions/open" do
      @signed_in_sessions = LabSession.where(:time_out => nil).order(:id)
      erb :signed_in_list
    end

    get "/new_mentor" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      erb :new_mentor
    end

    get "/mentors" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      erb :mentors
    end

    post "/mentors" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      halt(400, "Missing first name.") if params[:first_name].nil? || params[:first_name].empty?
      halt(400, "Missing last name.") if params[:last_name].nil? || params[:last_name].empty?
      halt(400, "Missing phone number.") if params[:phone_number].nil? || params[:phone_number].empty?
      Mentor.create(:first_name => params[:first_name], :last_name => params[:last_name],
                    :phone_number => params[:phone_number].gsub(/[^\d]/, "")[-10..-1])
      redirect "/mentors"
    end

    get "/mentors/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @mentor = Mentor[params[:id]]
      halt(400, "Invalid mentor.") if @mentor.nil?
      erb :delete_mentor
    end

    post "/mentors/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      @mentor = Mentor[params[:id]]
      halt(400, "Invalid mentor.") if @mentor.nil?
      @mentor.delete
      redirect "/mentors"
    end

    get "/suspect_lab_sessions" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_EDIT")
      erb :suspect_lab_sessions
    end

    get "/search" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_VIEW")
      erb :search
    end

    post "/search" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_VIEW")
      @start = params[:start_date]
      @end = params[:end_date]
      begin
        # Parse each date in the user's timezone to get correct DST offset per date
        start_time = user_time_zone.parse(@start + " 00:00:00")
        end_date_str = @end == "" ? @start : @end
        end_time = user_time_zone.parse(end_date_str + " 23:59:59")
        
        # Convert to UTC and then to DateTime for comparison with lab_session columns
        start_date = start_time.utc.to_datetime
        end_date = end_time.utc.to_datetime
      rescue
        halt(400, "Invalid date.")
      end
      if start_date > end_date
        halt(400, "Start date must be before end date.")
      end
      @query = LabSession.exclude(:time_out => nil)
                         .where { time_out >= start_date }
                         .where { time_in <= end_date }
                         .all
      erb :search
    end

    # Receives all SMS messages via Twilio.
    post "/sms" do
      content_type "application/xml"

      # Retrieve the mentor record using the sender phone number.
      phone_number = params[:From].gsub(/[^\d]/, "")[-10..-1]
      mentor = Mentor.where(:phone_number => phone_number).first
      halt(200, sms_response(["Error: Don't recognize sender's phone number."])) if mentor.nil?

      # First check for special control messages.
      if params[:Body].strip.downcase == "gtfo"
        # Sign everyone out all at once.
        LabSession.where(:time_out => nil).each do |lab_session|
          lab_session.update(:time_out => Time.now.utc, :mentor => mentor)
        end
        halt(200, sms_response(["All students signed out."]))
      end

      # Next, check for multiple IDs in the message.
      ids = params[:Body].strip.split(" ")
      messages = ids.map do |id|
        # Retrieve the student record using the body of the message.
        student = Student.get_by_id(id)
        if student.nil?
          "Error: No matching student."
        else
          # Find the open lab session and sign it out.
          lab_session = student.lab_sessions.select { |session| session.time_out.nil? }.first
          if lab_session.nil?
            "Error: #{student.first_name} #{student.last_name} is not signed in."
          else
            lab_session.update(:time_out => Time.now.utc, :mentor => mentor)
            "#{student.first_name} #{student.last_name} signed out after " +
                "#{lab_session.duration_hours.round(1)} hours."
          end
        end
      end
      halt(200, sms_response(messages))
    end

    get "/reindex_students" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("DATABASE_ADMIN")

      @reindex_preview = reindex_students_preview
      @reindex_result = session.delete(:reindex_students_result)
      @reindex_token = SecureRandom.hex(32)
      session[:reindex_students_preview] = reindex_students_preview_signature(@reindex_preview).merge("token" => @reindex_token)
      erb :reindex_students
    end

    post "/reindex_students" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("DATABASE_ADMIN")
      unless params[:confirmation] == "I want to reindex students."
        halt(400, "Type \"I want to reindex students.\" to confirm.")
      end

      expected_preview = session[:reindex_students_preview]
      expected_token = expected_preview.is_a?(Hash) ? expected_preview["token"].to_s : ""
      reindex_token = params[:reindex_token].to_s
      valid_token = !reindex_token.empty? &&
                    reindex_token.bytesize == expected_token.bytesize &&
                    Rack::Utils.secure_compare(reindex_token, expected_token)
      halt(403, "Reindex preview expired. Preview the roster again before continuing.") unless valid_token

      expected_signature = expected_preview.reject { |key, _value| key == "token" }
      reindex_preview = nil
      DB.transaction do
        reindex_preview = reindex_students_preview
        halt(409, "Members returned no students. Reindexing is blocked.") if reindex_preview[:blocked]
        unless expected_signature == reindex_students_preview_signature(reindex_preview)
          halt(409, "The Members roster or database changed after this preview. Preview the roster again before continuing.")
        end

        reindex_preview[:added_students].each do |student|
          Student.create(:id => student[:id], :first_name => student[:first_name], :last_name => student[:last_name])
        end
        reindex_preview[:updated_students].each do |student|
          replacement = student[:replacement]
          Student.where(:id => replacement[:id]).update(
            :first_name => replacement[:first_name],
            :last_name => replacement[:last_name]
          )
        end
        removed_ids = reindex_preview[:removed_students].map { |student| student[:id] }
        Student.where(:id => removed_ids).delete unless removed_ids.empty?
      end

      session.delete(:reindex_students_preview)
      session[:reindex_students_result] = {
        "added_count" => reindex_preview[:added_students].length,
        "updated_count" => reindex_preview[:updated_students].length,
        "removed_count" => reindex_preview[:removed_students].length,
        "unchanged_count" => reindex_preview[:unchanged_count]
      }
      redirect "/reindex_students"
    end

    get "/csv_report" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_VIEW_REPORT")
      content_type "text/csv"

      rows = []
      rows << ["Last Name", "First Name", "Student ID", "Project Hours", "Total # of Sign Outs"].join(",")
      Student.eager(:lab_sessions).order_by(:last_name).each do |student|
        rows << [student.last_name, student.first_name, student.id, student.project_hours, student.total_sessions_attended].join(",")
      end
      rows.join("\n")
    end

    def sms_response(messages)
      escaped = messages.map { |m| CGI.escapeHTML(m) }
      <<-END
        <Response>
          <Sms>#{escaped.join("</Sms><Sms>")}</Sms>
        </Response>
      END
    end

    get "/csv_attendance_report" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_VIEW_REPORT")
      content_type "text/csv"

      rows = []
      rows << ["Last Name", "First Name", "Student ID", "Attendance Percentage", "Project Hours", "Total # of Sign Outs"].join(",")
      students_by_id = Student.eager(:lab_sessions).all.each_with_object({}) { |s, h| h[s.id] = s }
      DB.fetch CALENDAR_STUDENT_INFO_QUERY do |row|
        student = students_by_id[row[:student_id]]
        next unless student
        build_percentage = ((100 * row[:required_attended_count].to_f/row[:required_count]).to_i rescue "0").to_s + "%"
        rows << [student.last_name, student.first_name, student.id, build_percentage, student.project_hours, student.total_sessions_attended].join(",")
      end
      rows.join("\n")
    end

    get "/reset_hours" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("DATABASE_ADMIN")

      cutoff_value = params[:cutoff_date].to_s
      @cutoff_date = cutoff_value.empty? ? user_time_zone.now.to_date : parse_reset_cutoff(cutoff_value)
      @preview = reset_activity_preview(@cutoff_date)
      @reset_result = session.delete(:reset_hours_result)
      @reset_token = SecureRandom.hex(32)
      session[:reset_hours_preview] = reset_preview_signature(@preview).merge("token" => @reset_token)
      erb :reset_hours
    end

    post "/reset_hours" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("DATABASE_ADMIN")
      halt(400, "Type \"I want to reset hours.\" to confirm.") unless params[:confirmation] == "I want to reset hours."

      cutoff_date = parse_reset_cutoff(params[:cutoff_date])
      expected_preview = session[:reset_hours_preview]
      expected_token = expected_preview.is_a?(Hash) ? expected_preview["token"].to_s : ""
      reset_token = params[:reset_token].to_s
      valid_token = !reset_token.empty? &&
                    reset_token.bytesize == expected_token.bytesize &&
                    Rack::Utils.secure_compare(reset_token, expected_token)
      halt(403, "Reset preview expired. Preview the reset again before continuing.") unless valid_token

      expected_signature = expected_preview.reject { |key, _value| key == "token" }
      deleted_counts = {}
      reset_preview = nil
      DB.transaction do
        reset_preview = reset_activity_preview(cutoff_date)
        unless expected_signature == reset_preview_signature(reset_preview)
          halt(409, "The database changed after this preview. Preview the reset again before continuing.")
        end
        unless reset_preview[:crossing_sessions] == 0
          halt(409, "Resolve open or cross-cutoff lab sessions before resetting hours.")
        end

        reset_preview[:datasets].each do |table, dataset|
          previewed_ids = dataset.select_map(:id)
          if previewed_ids.empty?
            deleted_counts[table.to_s] = 0
          else
            deleted_counts[table.to_s] = DB[table].where(:id => previewed_ids).delete
          end
        end
        batch_ids_to_delete = reset_preview[:batch_ids_to_delete]
        deleted_counts["build_schedule_batches"] = if batch_ids_to_delete.empty?
                                                       0
                                                     else
                                                       DB[:build_schedule_batches].where(:id => batch_ids_to_delete).delete
                                                     end
      end

      session.delete(:reset_hours_preview)
      session[:reset_hours_result] = {
        "cutoff_date" => cutoff_date.iso8601,
        "deleted_counts" => deleted_counts
      }
      redirect "/reset_hours?cutoff_date=#{cutoff_date.iso8601}"
    end

    get "/signout_automatic" do
      unless request.env["HTTP_X_REAL_IP"].nil?
        halt(400, "Invalid IP address; this route must be triggered internally.")
      end

      LabSession.where(:time_out => nil).each do |lab_session|
        offset_hours = CheesyCommon::Config.automatic_signout_offset_hours
        signout_time = (Time.now + offset_hours * 3600).utc

        lab_session.update(:time_out => signout_time, :mentor_name => "Automatic - Didn't Sign Out")
      end
    end
  end
end
