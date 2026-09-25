require_relative "hours_config"
require "twilio-ruby"

module CheesyHours
  class SmsWebhook
    def initialize
      return unless Config.program == "FRC"
      @production = Config.environment == "prod"
      token = Config.twilio_auth_token.to_s
      raise ArgumentError, "twilio_auth_token is required in config.json." if token.strip.empty?
      @validator = Twilio::Security::RequestValidator.new(token)
    rescue Config::NoValueFoundError
      raise if @production
    end

    def valid?(request)
      return false unless @validator && request.media_type == "application/x-www-form-urlencoded"
      form = request.POST
      return false unless form.values.all? { |value| value.is_a?(String) } &&
                          !form["From"].to_s.strip.empty? && form.key?("Body")

      # Nginx preserves the public Host but terminates HTTPS before forwarding to Ruby.
      url = @production ? request.url.sub(/\Ahttp:/, "https:") : request.url
      @validator.validate(url, form, request.env["HTTP_X_TWILIO_SIGNATURE"].to_s)
    end
  end
end
