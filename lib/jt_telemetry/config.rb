module JtTelemetry
  # Everything comes from ENV. Read on each call, so a changed ENV needs no reset.
  class Config
    DEFAULTS = {
      "SENTRY_TRACES_SAMPLE_RATE" => "0.1",
      "POSTHOG_KEY" => "phc_pMis3banzFK6hWH9RXdJDC6KJdyXCZqcbp3Jks36XoUE",
      "POSTHOG_HOST" => "https://t.joaotorr.es",
      "POSTHOG_UI_HOST" => "https://eu.posthog.com"
    }.freeze
    HEALTH_CHECK_PATH = "/up".freeze

    def initialize(env: ENV, rails_env: default_rails_env)
      @env = env
      @rails_env = rails_env.to_s
    end

    def enabled?
      value = present("TELEMETRY_ENABLED")
      value ? %w[1 true yes].include?(value.downcase) : @rails_env == "production"
    end

    # Raises at boot when telemetry is on, so a deploy missing APP_NAME fails loudly.
    def validate!
      app_name if enabled?
    end

    def app_name
      present("APP_NAME") or raise Error, "APP_NAME is required when telemetry is enabled"
    end

    def sentry?
      enabled? && !sentry_dsn.nil?
    end

    def sentry_dsn
      present("SENTRY_DSN")
    end

    def traces_sample_rate
      Float(fetch("SENTRY_TRACES_SAMPLE_RATE"))
    end

    def traces_sampler
      rate = traces_sample_rate
      ->(context) { context.dig(:env, "PATH_INFO") == HEALTH_CHECK_PATH ? 0.0 : rate }
    end

    def release
      present("KAMAL_VERSION")
    end

    def posthog_key
      fetch("POSTHOG_KEY")
    end

    def posthog_host
      fetch("POSTHOG_HOST")
    end

    def posthog_ui_host
      fetch("POSTHOG_UI_HOST")
    end

    private

    def present(name)
      value = @env[name].to_s.strip
      value unless value.empty?
    end

    def fetch(name)
      present(name) || DEFAULTS.fetch(name)
    end

    def default_rails_env
      defined?(Rails.env) ? Rails.env : ENV.fetch("RAILS_ENV", "development")
    end
  end
end
