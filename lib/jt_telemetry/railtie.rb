require "sentry-ruby"
require "sentry-rails"

module JtTelemetry
  class Railtie < Rails::Railtie
    initializer "jt_telemetry.sentry" do
      config = JtTelemetry.config
      config.validate!
      next unless config.sentry?

      Sentry.init do |sentry|
        sentry.dsn = config.sentry_dsn
        sentry.environment = Rails.env
        sentry.release = config.release if config.release
        sentry.send_default_pii = false
        sentry.traces_sampler = config.traces_sampler
      end
      Sentry.set_tags(app: config.app_name)
    end

    initializer "jt_telemetry.helper" do
      ActiveSupport.on_load(:action_view) { include JtTelemetry::Helper }
    end
  end
end
