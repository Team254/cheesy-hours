# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)
#
# The main class of the hours web server.

require "cgi"
require "pathological"
require "sinatra/base"

require "config/environment"
require "models"
require "wordpress_authentication"

module CheesyFrcHours
  class Server < Sinatra::Base
    include WordpressAuthentication

    set :sessions => true

    # Enforce authentication for all routes except login and the main page.
    before do
      @user_info = JSON.parse(session[:user_info]) rescue nil
      authenticate! unless ["/", "/login"].include?(request.path)
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
      erb :index
    end

    get "/reindex_students" do
      halt(400, "Need to be an administrator.") unless @user_info["administrator"] == "1"

      # TODO(patrick): Implement once there's an appropriate API on the Wordpress site.
      "Implement me!"
    end
  end
end
