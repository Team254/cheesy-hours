# -*- encoding: utf-8 -*-
$:.unshift File.expand_path("../lib", __FILE__)
require "pathological/version"

Gem::Specification.new do |s|
  s.name = "pathological"
  s.version = Pathological::VERSION
  s.platform    = Gem::Platform::RUBY

  s.required_rubygems_version = Gem::Requirement.new(">=0") if s.respond_to? :required_rubygems_version=
  s.specification_version = 2 if s.respond_to? :specification_version=

  s.authors = "Daniel MacDougall", "Caleb Spare", "Evan Chan"
  s.email = "dmac@ooyala.com", "caleb@ooyala.com", "ev@ooyala.com"
  s.homepage = "http://www.ooyala.com"
  s.rubyforge_project = "pathological"

  s.summary = "A nice way to manage your project's require paths."
  s.description = <<-DESCRIPTION
    Pathological provides a way to manage a project's require paths by using a small config file that
    indicates all directories to include in the load path.
  DESCRIPTION

  s.files = `git ls-files`.split("\n").reject { |f| f == ".gitignore" }
  s.require_paths = ["lib"]

  # Require rr >= 1.0.3 and scope >= 0.2.3 for mutual compatibility.
  s.add_development_dependency "rr", ">= 1.0.3"
  s.add_development_dependency "scope", ">= 0.2.3"
  s.add_development_dependency "fakefs"
  s.add_development_dependency "rake"
  s.add_development_dependency "dedent"
end
