require "erb"
require "json"
require_relative "jt_telemetry/version"
require_relative "jt_telemetry/config"
require_relative "jt_telemetry/tags"
require_relative "jt_telemetry/redactor"
require_relative "jt_telemetry/helper"
require_relative "jt_telemetry/railtie" if defined?(Rails::Railtie)

module JtTelemetry
  def self.config
    @config ||= Config.new
  end

  # config.jt_telemetry.redact_paths, or none outside a Rails app.
  def self.redact_paths
    defined?(Rails.application) && Rails.application ? Rails.application.config.jt_telemetry.redact_paths : []
  end

  # The <script> tag for the <head>, as a plain string. Layouts call
  # Helper#jt_telemetry_tags instead; this is for apps that serve static HTML.
  def self.tags(nonce: nil, config: self.config, redact_paths: self.redact_paths)
    Tags.new(config, redact_paths:).render(nonce:)
  end
end
