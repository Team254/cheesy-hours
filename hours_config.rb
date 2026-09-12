require "cheesy-common"

module CheesyHours
  module Config
    class InvalidProgramError < StandardError; end

    PROGRAM_PROFILES = {
      "FRC" => "frc",
      "FTC" => "ftc"
    }.freeze
    NoValueFoundError = CheesyCommon::Config::NoValueFoundError

    def self.program_profile
      program = ENV.fetch("HOURS_PROGRAM", "FRC").upcase
      profile_name = PROGRAM_PROFILES.fetch(program) do
        raise InvalidProgramError, "HOURS_PROGRAM must be FRC or FTC."
      end

      profiles = CheesyCommon::Config.all_configs
      return profiles[profile_name] if profiles.key?(profile_name)
      return {} unless ENV.key?("HOURS_PROGRAM")

      raise InvalidProgramError, "No '#{profile_name}' profile found in config.json."
    end

    def self.method_missing(method, *arguments, &block)
      return super unless arguments.empty? && block.nil?

      key = method.to_s
      profile = program_profile
      return CheesyCommon::Config.decode_param(profile[key]) if profile.key?(key)

      CheesyCommon::Config.public_send(method)
    end

    def self.respond_to_missing?(method, include_private = false)
      key = method.to_s
      program_profile.key?(key) ||
        CheesyCommon::Config.all_configs.values.any? { |config| config.key?(key) } ||
        super
    end
  end
end
