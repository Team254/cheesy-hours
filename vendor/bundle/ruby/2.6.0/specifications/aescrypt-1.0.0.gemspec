# -*- encoding: utf-8 -*-
# stub: aescrypt 1.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "aescrypt".freeze
  s.version = "1.0.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Gurpartap Singh".freeze]
  s.date = "2012-07-31"
  s.description = "Simple AES encryption / decryption for Ruby".freeze
  s.email = ["contact@gurpartap.com".freeze]
  s.homepage = "http://github.com/Gurpartap/aescrypt".freeze
  s.rubygems_version = "3.0.3.1".freeze
  s.summary = "AESCrypt is a simple to use, opinionated AES encryption / decryption Ruby gem that just works.".freeze

  s.installed_by_version = "3.0.3.1" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    else
      s.add_dependency(%q<rake>.freeze, [">= 0"])
    end
  else
    s.add_dependency(%q<rake>.freeze, [">= 0"])
  end
end
