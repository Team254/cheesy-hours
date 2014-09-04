# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# The main class of the hours web server.

require "active_support/time"
require "cgi"
require "pathological"
require "sinatra/base"

require "config/environment"
require "models"
require "wordpress_authentication"

module CheesyFrcHours
  class Server < Sinatra::Base
    include WordpressAuthentication

    use Rack::Session::Cookie, :key => "rack.session"

    SIGNIN_IP_WHITELIST = ["198.123.", "128.102."]

    # Enforce authentication for all non-public routes.
    before do
      @user_info = JSON.parse(session[:user_info]) rescue nil
      authenticate! unless ["/", "/login", "/signin", "/sms"].include?(request.path)
    end

    def authenticate!
      redirect "/login?redirect=#{request.path}" if @user_info.nil?
    end

    get "/login" do
      @redirect = params[:redirect] || "/"

      # Authenticate against Wordpress.
      wordpress_user_info = get_wordpress_user_info
      if wordpress_user_info
        wordpress_user_info.delete("signature")
        @user_info = wordpress_user_info
        session[:user_info] = @user_info.to_json
        redirect @redirect
      else
        redirect_path = CGI.escape("#{BASE_ADDRESS}/login?redirect=#{@redirect}")
        redirect "http://www.team254.com/wp-login.php?redirect_to=#{redirect_path}"
      end
    end

    get "/logout" do
      session[:user_info] = nil
      redirect "/"
    end

    get "/" do
      @signed_in_sessions = LabSession.where(:time_out => nil)
      erb :index
    end

    post "/signin" do
      @student = Student[params[:student_id]] || Student["21" + params[:student_id]]
      halt(400, "Invalid student.") if @student.nil?

      # Restrict sign-ins to the NASA Lab's IP address ranges.
      unless SIGNIN_IP_WHITELIST.any? { |ip| request.env["HTTP_X_REAL_IP"].start_with?(ip) }
        halt(400, "Invalid IP address. Must sign in from the NASA Lab.")
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
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      @student = Student[params[:id]]
      halt(400, "Invalid student.") if @student.nil?
      erb :edit_lab_session
    end

    post "/students/:id/new_lab_session" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      student = Student[params[:id]]
      halt(400, "Invalid student.") if student.nil?
      student.add_lab_session(:time_in => params[:time_in], :time_out => params[:time_out],
                              :notes => params[:notes],
                              :mentor_name => params[:time_out].empty? ? nil : @user_info["name"])
      redirect params[:referrer] || "/leader_board"
    end

    get "/lab_sessions/:id/edit" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @referrer = request.referrer
      erb :edit_lab_session
    end

    post "/lab_sessions/:id/edit" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      if !params[:time_out].empty? && @lab_session.time_out.nil?
        mentor_name = @user_info["name"]
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
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @referrer = request.referrer
      erb :delete_lab_session
    end

    post "/lab_sessions/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      @lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if @lab_session.nil?
      @lab_session.delete
      redirect params[:referrer] || "/leader_board"
    end

    get "/lab_sessions/:id/sign_out" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      lab_session = LabSession[params[:id]]
      halt(400, "Invalid lab session.") if lab_session.nil?
      lab_session.update(:time_out => Time.now, :mentor_name => @user_info["name"])
      redirect "/"
    end

    get "/lab_sessions/open" do
      @signed_in_sessions = LabSession.where(:time_out => nil).order(:id)
      erb :signed_in_list
    end

    get "/new_mentor" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      erb :new_mentor
    end

    get "/mentors" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      erb :mentors
    end

    post "/mentors" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      halt(400, "Missing first name.") if params[:first_name].nil? || params[:first_name].empty?
      halt(400, "Missing last name.") if params[:last_name].nil? || params[:last_name].empty?
      halt(400, "Missing phone number.") if params[:phone_number].nil? || params[:phone_number].empty?
      Mentor.create(:first_name => params[:first_name], :last_name => params[:last_name],
                    :phone_number => params[:phone_number].gsub(/[^\d]/, "")[-10..-1])
      redirect "/mentors"
    end

    get "/mentors/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
      @mentor = Mentor[params[:id]]
      halt(400, "Invalid mentor.") if @mentor.nil?
      erb :delete_mentor
    end

    post "/mentors/:id/delete" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
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

      # Check for multiple IDs in the message.
      ids = params[:Body].split(" ")
      messages = ids.map do |id|
        # Retrieve the student record using the body of the message.
        student = Student[id] || Student["21" + id]
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
      halt(400, "Need to be an administrator.") unless @user_info["administrator"] == "1"

      students = get_wordpress_student_list
      Student.truncate
      students.each do |student|
        next if student["student_id"] == "254254"  # Ignore users having the special invite code.
        begin
          Student.create(:id => student["student_id"], :first_name => student["first_name"],
                         :last_name => student["last_name"])
        rescue Sequel::UniqueConstraintViolation
          # Ignore duplicate student records.
        end
      end
      "Successfully imported #{Student.all.size} students."
    end

    get "/csv_report" do
      halt(403, "Insufficient permissions.") unless @user_info["mentor"] == 1
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
