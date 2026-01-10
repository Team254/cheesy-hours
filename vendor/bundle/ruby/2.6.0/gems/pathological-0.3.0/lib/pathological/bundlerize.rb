# Make bundler compatible with Pathological (that is, enable Bundler projects to be run from anywhere as
# Pathological allows) by setting the BUNDLE_GEMFILE env variable.
#
# To use this, you *must* require pathological/bundlerize before you require bundler/setup.

require "pathological/base"

Pathological.bundlerize_mode
Pathological.add_paths!
