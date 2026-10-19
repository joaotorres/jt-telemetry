require "sentry-ruby"
require "sentry-rails"

module JtTelemetry
  class Railtie < Rails::Railtie
    config.jt_telemetry = ActiveSupport::OrderedOptions.new
    config.jt_telemetry.redact_paths = []

    initializer "jt_telemetry.sentry" do
      config = JtTelemetry.config
      # Read on each event, so paths declared in a config/initializers file,
      # which loads after this initializer, still apply.
      redact = ->(event, hint) { Redactor.new(JtTelemetry.redact_paths).call(event, hint) }
      Rails.logger.warn(config.warning) if config.warning
      next unless config.sentry?

      Sentry.init do |sentry|
        sentry.dsn = config.sentry_dsn
        sentry.environment = Rails.env
        sentry.release = config.release if config.release
        sentry.send_default_pii = false
        sentry.traces_sampler = config.traces_sampler
        sentry.before_send = redact
        sentry.before_send_transaction = redact
      end
      Sentry.set_tags(app: config.app_name)
    end

    initializer "jt_telemetry.helper" do
      ActiveSupport.on_load(:action_view) { include JtTelemetry::Helper }
    end
  end
end
