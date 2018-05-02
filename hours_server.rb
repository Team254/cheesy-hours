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
          redirect "#{CheesyCommon::Config.members_url}?site=vexhours&path=#{request.path}"
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
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      @student = Student[params[:id]]
      halt(400, "Invalid student.") if @student.nil?
      erb :edit_lab_session
    end

    post "/students/:id/new_lab_session" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      student = Student[params[:id]]
      halt(400, "Invalid student.") if student.nil?
      student.add_lab_session(:time_in => params[:time_in], :time_out => params[:time_out],
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
      @lab_session.update(:time_in => params[:time_in], :time_out => params[:time_out],
                          :notes => params[:notes], :mentor_name => mentor_name)
      redirect params[:referrer] || "/leader_board"
    end

    get "/lab_sessions/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @referrer = request.referrer
      erb :delete_lab_session
    end

    post "/lab_sessions/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user.has_permission?("VEXHOURS_EDIT")
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

    # Receives all SMS messages via Twilio.
    post "/sms" do
      content_type "application/xml"

      # Retrieve the mentor record using the sender phone number.
      phone_number = params[:From].gsub(/[^\d]/, "")[-10..-1]
      mentor = Mentor.where(:phone_number => phone_number).first
      halt(200, sms_response(["Error: Don't recognize sender's phone number."])) if mentor.nil?

      # First check for special control messages.
      if params[:Body].downcase == "gtfo"
        # Sign everyone out all at once.
        LabSession.where(:time_out => nil).each do |lab_session|
          lab_session.update(:time_out => Time.now, :mentor => mentor)
        end
        halt(200, sms_response(["All students signed out."]))
      end

      # Next, check for multiple IDs in the message.
      ids = params[:Body].split(" ")
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
      rows << ["Last Name", "First Name", "Student ID", "Project Hours"].join(",")
      Student.order_by(:last_name).each do |student|
        rows << [student.last_name, student.first_name, student.id, student.project_hours].join(",")
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
  end
end
