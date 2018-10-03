# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# The main class of the hours web server.

require "active_support/time"
require "cgi"
require "cheesy-common"
require "pathological"
require "sinatra/base"

require "models"

module CheesyHours
  class Server < Sinatra::Base
    use Rack::Session::Cookie, :key => "rack.session", :expire_after => 3600

    # Enforce authentication for all non-public routes.
    before do
      @user = CheesyCommon::Auth.get_user(request)
      if @user.nil?
        session[:user] = nil
        unless ["/", "/signin", "/sms"].include?(request.path)
          redirect "#{CheesyCommon::Config.members_url}?site=nontech-hours&path=#{request.path}"
        end
      else
          session[:user] = @user
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

      redirect "/"
    end

    get "/leader_board" do
      erb :leader_board
    end

    get "/students/:id" do
      @student = Student[params[:id]]
      halt(400, "Invalid student.") if @student.nil?
      erb :student
    end

    get "/students/:id/new_lab_session" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("NONTECH_HOURS_EDIT")
      @student = Student[params[:id]]
      halt(400, "Invalid student.") if @student.nil?
      erb :edit_lab_session
    end

    post "/students/:id/new_lab_session" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("NONTECH_HOURS_EDIT")
      student = Student[params[:id]]
      halt(400, "Invalid student.") if student.nil?
      student.add_lab_session(:time_in => params[:time_in], :time_out => params[:time_out],
                              :notes => params[:notes],
                              :mentor_name => params[:time_out].empty? ? nil : @user.name_display)
      redirect params[:referrer] || "/leader_board"
    end

    get "/lab_sessions/:id/edit" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("NONTECH_HOURS_EDIT")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @referrer = request.referrer
      erb :edit_lab_session
    end

    post "/lab_sessions/:id/edit" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("NONTECH_HOURS_EDIT")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      if !params[:time_out].empty? && @lab_session.time_out.nil?
        mentor_name = @user.name_display
      elsif params[:time_out].empty? && @lab_session.time_out
        mentor_name = nil
      else
        mentor_name = @lab_session.mentor_name
      end
      @lab_session.update(:time_in => params[:time_in], :time_out => params[:time_out],
                          :notes => params[:notes], :mentor_name => mentor_name)
      redirect params[:referrer] || "/leader_board"
    end

    get "/lab_sessions/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("NONTECH_HOURS_EDIT")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @referrer = request.referrer
      erb :delete_lab_session
    end

    post "/lab_sessions/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("NONTECH_HOURS_EDIT")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @lab_session.delete
      redirect params[:referrer] || "/leader_board"
    end

    get "/lab_sessions/:id/sign_out" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("NONTECH_HOURS_EDIT")
      lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if lab_session.nil?
      lab_session.update(:time_out => Time.now, :mentor_name => @user.name_display)
      redirect "/"
    end

    get "/lab_sessions/open" do
      @signed_in_sessions = LabSession.where(:time_out => nil).order(:id)
      erb :signed_in_list
    end

    get "/reindex_students" do
      unless @user.has_permission?("DATABASE_ADMIN")
        halt(400, "Need to be an administrator.")
      end

      students = CheesyCommon::Auth.find_users_with_permission("HOURS_SIGN_IN")
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
  end
end
