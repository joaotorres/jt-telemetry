require_relative "lib/jt_telemetry/version"

Gem::Specification.new do |spec|
  spec.name = "jt_telemetry"
  spec.version = JtTelemetry::VERSION
  spec.authors = ["João Torres"]
  spec.summary = "Sentry and PostHog wiring shared by my Rails apps"
  spec.homepage = "https://github.com/joaotorres/jt_telemetry"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]

  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "sentry-rails", "~> 7.1"
  spec.add_dependency "sentry-ruby", "~> 7.1"
end
