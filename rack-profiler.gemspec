# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rack/profiler/version'

Gem::Specification.new do |spec|
  spec.name          = "rack-profiler"
  spec.version       = Rack::Profiler::VERSION
  spec.authors       = ["Luca Ongaro", "Luca Tironi"]
  spec.email         = ["lukeongaro@gmail.com"]
  spec.summary       = "A simple profiler for Rack applications"
  spec.description   = "A simple profiler for Rack applications, only depending on ActiveSupport::Notifications"
  spec.homepage      = "https://github.com/dawanda/rack-profiler"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 3.0.0"

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
end
