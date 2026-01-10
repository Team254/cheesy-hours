# -*- encoding: utf-8 -*-
# stub: pathological 0.3.0 ruby lib

Gem::Specification.new do |s|
  s.name = "pathological".freeze
  s.version = "0.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Daniel MacDougall".freeze, "Caleb Spare".freeze, "Evan Chan".freeze]
  s.date = "2012-09-20"
  s.description = "    Pathological provides a way to manage a project's require paths by using a small config file that\n    indicates all directories to include in the load path.\n".freeze
  s.email = ["dmac@ooyala.com".freeze, "caleb@ooyala.com".freeze, "ev@ooyala.com".freeze]
  s.homepage = "http://www.ooyala.com".freeze
  s.rubygems_version = "3.0.3.1".freeze
  s.summary = "A nice way to manage your project's require paths.".freeze

  s.installed_by_version = "3.0.3.1" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 2

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<rr>.freeze, [">= 1.0.3"])
      s.add_development_dependency(%q<scope>.freeze, [">= 0.2.3"])
      s.add_development_dependency(%q<fakefs>.freeze, [">= 0"])
      s.add_development_dependency(%q<rake>.freeze, [">= 0"])
      s.add_development_dependency(%q<dedent>.freeze, [">= 0"])
    else
      s.add_dependency(%q<rr>.freeze, [">= 1.0.3"])
      s.add_dependency(%q<scope>.freeze, [">= 0.2.3"])
      s.add_dependency(%q<fakefs>.freeze, [">= 0"])
      s.add_dependency(%q<rake>.freeze, [">= 0"])
      s.add_dependency(%q<dedent>.freeze, [">= 0"])
    end
  else
    s.add_dependency(%q<rr>.freeze, [">= 1.0.3"])
    s.add_dependency(%q<scope>.freeze, [">= 0.2.3"])
    s.add_dependency(%q<fakefs>.freeze, [">= 0"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<dedent>.freeze, [">= 0"])
  end
end
