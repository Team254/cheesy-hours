# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# The main class of the hours web server.

require "active_support/time"
require "cgi"
require "cheesy-common"
require "pathological"
require "sinatra/base"
require "json"

require "models"
require "constants"
require "queries"

module CheesyHours
  class Server < Sinatra::Base
    use Rack::Session::Cookie, :key => "rack.session", :expire_after => 3600

    configure do
      if ENV["HOURS_AUTO_SEED_TEST_STUDENTS"] == "1"
        require_relative "script/seed_test_students"
        count = (ENV["COUNT"] || "30").to_i
        start_id = (ENV["START_ID"] || "900000").to_i
        SeedTestStudents.run(count: count, start_id: start_id)
      end
    end
    # Enforce authentication for all non-public routes.
    before do
      if ENV["HOURS_BYPASS_AUTH"] == "1"
        # Local dev bypass for Team 254 SSO.
        dev_bcp_id = (ENV["HOURS_BYPASS_BCP_ID"] || "900001").to_i
        @user = CheesyCommon::User.new(
          "name_display" => "Dev User",
          "bcp_id" => dev_bcp_id,
          "permissions" => ["HOURS_SIGN_IN", "HOURS_EDIT", "VEXHOURS_EDIT", "HOURS_DELETE", "HOURS_VIEW_REPORT", "DATABASE_ADMIN"]
        )
        session[:user] = @user
      else
        @user = CheesyCommon::Auth.get_user(request)
        if @user.nil?
          session[:user] = nil
          # Note: signin_internal blocks all outside sources (localhost only)
          unless ["/", "/sms", "/signin_internal", "/signout_automatic"].include?(request.path)
            redirect "#{CheesyCommon::Config.members_url}?site=ftchours&path=#{request.path}"
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
      if !ip_whitelist.empty? && ip_whitelist.none? { |ip| request.env["HTTP_X_REAL_IP"].start_with?(ip) }
        halt(400, "Invalid IP address. Must sign in from the Robotics Lab.")
      end

      # Check for existing open lab sessions.
      unless LabSession.where(:student_id => @student.id, :time_out => nil).empty?
        halt(400, "An open lab session already exists for student #{@student.id}.")
      end
      @student.add_lab_session(:time_in => Time.now)

      # Add an optional build to the database if necessary.
      # (If today is not mandatory and the optional build is not in the database)
      currentUserTime = DateTime.now.in_time_zone(USER_TIME_ZONE)
      if REQUIRED_BUILD_DAYS.include?(currentUserTime.strftime("%A")) &&
          OptionalBuild.where(:date => currentUserTime.strftime("%Y-%m-%d")).empty?
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
      @student.add_lab_session(:time_in => Time.now)

      "Success"
    end

    get "/leader_board" do
      erb :leader_board
    end

    get "/calendar" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      today = Date.today
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

    get "/optionalize_past_offdays" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @referrer = request.referrer
      erb :optionalize_past_offdays
    end

    post "/optionalize_past_offdays" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))

      DB.fetch BUILD_DAYS_QUERY do |row|
        if !REQUIRED_BUILD_DAYS.include?(row[:build_date].strftime("%A"))
          OptionalBuild.create(:date => row[:build_date]) rescue nil
        end
      end

      redirect params[:referrer]
    end

    get "/schedule_optional" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @referrer = request.referrer
      @date = params[:date]
      erb :optional_build_scheduler
    end

    post "/schedule_optional" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      halt(400, "Invalid date.") if params[:date].nil?|| params[:date] == ""

      OptionalBuild.create(:date => params[:date]) if OptionalBuild.where(:date => params[:date]).empty?

      redirect params[:referrer]
    end

    get "/delete_optional/:date" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @referrer = request.referrer

      erb :delete_optional_build
    end

    post "/delete_optional/:date" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      OptionalBuild.where(:date => params[:date]).delete

      redirect params[:referrer]
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
      LabSession.where(Sequel.lit("DATE(time_in) = ?", date)).update(:excluded_from_total => true)

      redirect params[:referrer]
    end

    get "/schedule_build_day" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @referrer = request.referrer
      @date = params[:date]
      erb :schedule_build_day
    end

    post "/schedule_build_day" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      halt(400, "Invalid date.") if params[:date].nil? || params[:date] == ""
      halt(400, "Invalid optional value.") if params[:optional].nil?

      optional = params[:optional] == "1" || params[:optional] == "true"
      ScheduledBuildDay.create(:date => params[:date], :optional => optional) if ScheduledBuildDay.where(:date => params[:date]).empty?

      redirect params[:referrer]
    end

    get "/my_attendance" do
      halt(403, "You must be logged in.") if @user.nil?
      @student = Student[@user.bcp_id]
      halt(400, "Student record not found. Please contact an administrator.") if @student.nil?
      
      today = Date.today
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
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @student = Student[params[:id]]
      halt(400, "Invalid student.") if @student.nil?
      @referrer = request.referrer
      if !params[:date].nil?
        @date = params[:date]
      end
      erb :mark_excused
    end

    post "/students/:id/mark_excused" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      halt(400, "Missing date.") if params[:date].nil? || params[:date] == ""
      ExcusedSession.create(:date => params[:date], :student_id => params[:id])
      redirect params[:referrer]
    end

    get "/students/:id/excusals/:date/delete" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @excusal = ExcusedSession.where(:date => params[:date], :student_id => params[:id]).first
      halt(400, "Invalid excusal.") if @excusal.nil?
      @referrer = request.referrer
      erb :delete_excusal
    end

    post "/students/:id/excusals/:date/delete" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @excusal = ExcusedSession.where(:date => params[:date], :student_id => params[:id]).first
      halt(400, "Invalid excusal.") if @excusal.nil?
      @excusal.delete
      redirect params[:referrer]
    end

    get "/students/:id/new_lab_session" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
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
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      student = Student[params[:id]]
      halt(400, "Invalid student.") if student.nil?
      student.add_lab_session(:time_in => DateTime.parse(params[:time_in]).utc,
                              :time_out => DateTime.parse(params[:time_out]).utc,
                              :notes => params[:notes],
                              :mentor_name => params[:time_out].empty? ? nil : @user.name_display)
      redirect params[:referrer] || "/leader_board"
    end

    get "/lab_sessions/:id/edit" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @referrer = request.referrer
      erb :edit_lab_session
    end

    post "/lab_sessions/:id/edit" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      if !params[:time_out].empty? && @lab_session.time_out.nil?
        mentor_name = @user.name_display
      elsif params[:time_out].empty? && @lab_session.time_out
        mentor_name = nil
      else
        mentor_name = @lab_session.mentor_name
      end
      @lab_session.update(
        :time_in => DateTime.parse(params[:time_in]).utc,
        :time_out => DateTime.parse(params[:time_out]).utc,
        :notes => params[:notes],
        :mentor_name => mentor_name,
        :excluded_from_total => params[:excluded_from_total] == "on"
      )
      redirect params[:referrer] || "/leader_board"
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
      redirect params[:referrer] || "/leader_board"
    end

    get "/lab_sessions/:id/sign_out" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if lab_session.nil?
      lab_session.update(:time_out => Time.now, :mentor_name => @user.name_display)
      redirect "/"
    end

    get "/lab_sessions/open" do
      @signed_in_sessions = LabSession.where(:time_out => nil).order(:id)
      erb :signed_in_list
    end

    get "/new_mentor" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      erb :new_mentor
    end

    get "/mentors" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      erb :mentors
    end

    post "/mentors" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      halt(400, "Missing first name.") if params[:first_name].nil? || params[:first_name].empty?
      halt(400, "Missing last name.") if params[:last_name].nil? || params[:last_name].empty?
      halt(400, "Missing phone number.") if params[:phone_number].nil? || params[:phone_number].empty?
      Mentor.create(:first_name => params[:first_name], :last_name => params[:last_name],
                    :phone_number => params[:phone_number].gsub(/[^\d]/, "")[-10..-1])
      redirect "/mentors"
    end

    get "/mentors/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      @mentor = Mentor[params[:id]]
      halt(400, "Invalid mentor.") if @mentor.nil?
      erb :delete_mentor
    end

    post "/mentors/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      @mentor = Mentor[params[:id]]
      halt(400, "Invalid mentor.") if @mentor.nil?
      @mentor.delete
      redirect "/mentors"
    end

    get "/mentor_checkins" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @mentor_checkins = MentorCheckin.order_by(:id).reverse
      erb :mentor_checkins
    end

    get "/mentor_checkins/:id/delete" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @mentor_checkin = MentorCheckin[params[:id]]
      halt(400, "Invalid mentor_checkin.") if @mentor_checkin.nil?
      @referrer = request.referrer
      erb :delete_mentor_checkin
    end

    post "/mentor_checkins/:id/delete" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      mentor_checkin = MentorCheckin[params[:id]]
      halt(400, "Invalid mentor_checkin.") if mentor_checkin.nil?
      mentor_checkin.delete
      redirect params[:referrer] || "/mentor_checkins"
    end

    get "/suspect_lab_sessions" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      erb :suspect_lab_sessions
    end

    get "/search" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      erb :search
    end

    post "/search" do
      halt(403, "Insufficient permissions.") unless (@user.has_permission?("HOURS_EDIT") || @user.has_permission?("VEXHOURS_EDIT"))
      @start = params[:start_date]
      @end = params[:end_date]
      begin
        offset = Time.now.in_time_zone(USER_TIME_ZONE).formatted_offset
        start_date = DateTime.parse(@start).change(offset: offset)
        end_date = DateTime.parse(@end == "" ? @start : @end).change(offset: offset) + 1
      rescue
        halt(400, "Invalid date.")
      end
      if start_date > end_date
        halt(400, "Start date must be before end date.")
      end
      @query = []
      LabSession.each do |lab_session|
        if !lab_session.time_out.nil? && lab_session.time_out >= start_date && lab_session.time_in <= end_date
          @query << lab_session
        end
      end
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
          lab_session.update(:time_out => Time.now, :mentor => mentor)
        end
        halt(200, sms_response(["All students signed out."]))
      elsif params[:Body].strip.downcase == "here"
        # Register a mentor check-in.
        MentorCheckin.create(mentor: mentor, time_in: Time.now)
        halt(200, sms_response(["Checked in #{mentor.first_name} #{mentor.last_name}."]))
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
            lab_session.update(:time_out => Time.now, :mentor => mentor)
            "#{student.first_name} #{student.last_name} signed out after " +
                "#{lab_session.duration_hours.round(1)} hours."
          end
        end
      end
      halt(200, sms_response(messages))
    end

    get "/reindex_students" do
      unless @user.has_permission?("DATABASE_ADMIN")
        halt(400, "Need to be an administrator.")
      end

      students = CheesyCommon::Auth.find_users_with_permission("EVENTS_SIGNUP_EVENT")
      Student.truncate
      students.each do |student|
        Student.create(:id => student.bcp_id, :first_name => student.name[1], :last_name => student.name[0])
      end
      "Successfully imported #{Student.all.size} students."
    end

    get "/csv_report" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_VIEW_REPORT")
      content_type "text/csv"

      rows = []
      rows << ["Last Name", "First Name", "Student ID", "Project Hours", "Total # of Sign Outs"].join(",")
      Student.order_by(:last_name).each do |student|
        rows << [student.last_name, student.first_name, student.id, student.project_hours, student.total_sessions_attended].join(",")
      end
      rows.join("\n")
    end

    def sms_response(messages)
      <<-END
        <Response>
          <Sms>#{messages.join("</Sms><Sms>")}</Sms>
        </Response>
      END
    end

    get "/csv_attendance_report" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("HOURS_VIEW_REPORT")
      content_type "text/csv"

      rows = []
      rows << ["Last Name", "First Name", "Student ID", "Attendance Percentage", "Project Hours", "Total # of Sign Outs"].join(",")
      DB.fetch CALENDAR_STUDENT_INFO_QUERY do |row|
        student = Student[row[:student_id]]
        build_percentage = ((100 * row[:required_attended_count].to_f/row[:required_count]).to_i rescue "0").to_s + "%"
        rows << [student.last_name, student.first_name, student.id, build_percentage, student.project_hours, student.total_sessions_attended].join(",")
      end
      rows.join("\n")
    end

    get "/reset_hours" do
      unless @user.has_permission?("DATABASE_ADMIN")
        halt(400, "Need to be an administrator.")
      end

      DB[:lab_sessions].where(Sequel[:time_out] < DateTime.new(2018, 1, 6.0)).delete
      "Reset Hours"
    end

    get "/signout_automatic" do
      unless request.env["HTTP_X_REAL_IP"].nil?
        halt(400, "Invalid IP address; this route must be triggered internally.")
      end

      LabSession.where(:time_out => nil).each do |lab_session|
        offset_hours = CheesyCommon::Config.automatic_signout_offset_hours
        offset_hours -= 1 if Time.now.in_time_zone(USER_TIME_ZONE).dst?
        signout_time = Time.now + offset_hours * 3600

        lab_session.update(:time_out => signout_time, :mentor_name => "Automatic - Didn't Sign Out")
      end
    end
  end
end
