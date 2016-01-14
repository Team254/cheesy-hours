# Copyright 2013 Team 254. All Rights Reserved.
# @author pat@patfairbank.com (Patrick Fairbank)

require "httparty"
require "pathological"
require "json"

require "config/environment"

module CheesyFrcHours
  # Helper mixin for third-party authentication using Wordpress.
  module WordpressAuthentication
    STUDENT_LIST_URL = "http://www.team254.com/auth/student_list.php"

    def wordpress_cookie
      request.cookies[request.cookies.keys.select { |key| key =~ /wordpress_logged_in_[0-9a-f]{32}/ }.first]
    end

    # Returns a hash of user info if logged in to Wordpress, or nil otherwise.
    def get_wordpress_user_info
      if wordpress_cookie
        response = HTTParty.get("#{WORDPRESS_AUTH_URL}?cookie=#{URI.encode(wordpress_cookie)}")
        return JSON.parse(response.body) if response.code == 200
      end
      return nil
    end

    # Returns the list of students from the Wordpress API if logged in.
    def get_wordpress_student_list
      response = HTTParty.get("#{STUDENT_LIST_URL}?cookie=#{URI.encode(wordpress_cookie)}")
      unless response.code == 200
        raise "Failed to retrieve student list."
      end
      return JSON.parse(response.body)
    end
  end
end
