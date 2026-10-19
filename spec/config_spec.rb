require "spec_helper"

RSpec.describe JtTelemetry::Config do
  def config(env = {}, rails_env: "production")
    described_class.new(env:, rails_env:)
  end

  let(:named) { { "APP_NAME" => "onset" } }

  describe "#enabled?" do
    it "defaults to on in production and off elsewhere" do
      expect(config(named, rails_env: "production")).to be_enabled
      expect(config(named, rails_env: "development")).not_to be_enabled
      expect(config(named, rails_env: "test")).not_to be_enabled
    end

    it "follows TELEMETRY_ENABLED when set" do
      expect(config(named.merge("TELEMETRY_ENABLED" => "false"), rails_env: "production")).not_to be_enabled
      expect(config(named.merge("TELEMETRY_ENABLED" => "true"), rails_env: "development")).to be_enabled
      expect(config(named.merge("TELEMETRY_ENABLED" => "1"), rails_env: "development")).to be_enabled
    end

    it "treats a blank TELEMETRY_ENABLED as unset" do
      expect(config(named.merge("TELEMETRY_ENABLED" => " "), rails_env: "production")).to be_enabled
    end

    it "is off without APP_NAME, instead of stopping the boot" do
      expect(config({}, rails_env: "production")).not_to be_enabled
      expect(config({ "APP_NAME" => " " }, rails_env: "production")).not_to be_enabled
    end

    it "is off under SECRET_KEY_BASE_DUMMY, as in assets:precompile, whatever else is set" do
      expect(config(named.merge("SECRET_KEY_BASE_DUMMY" => "1"), rails_env: "production")).not_to be_enabled
      expect(config(named.merge("SECRET_KEY_BASE_DUMMY" => "1", "TELEMETRY_ENABLED" => "true"))).not_to be_enabled
    end
  end

  describe "#warning" do
    it "says telemetry is off when it was asked for without APP_NAME" do
      expect(config({}, rails_env: "production").warning).to match(/APP_NAME is not set/)
      expect(config({ "TELEMETRY_ENABLED" => "true" }, rails_env: "development").warning).to match(/APP_NAME/)
    end

    it "is nil when telemetry runs, or was never asked for" do
      expect(config(named).warning).to be_nil
      expect(config({}, rails_env: "development").warning).to be_nil
      expect(config({ "TELEMETRY_ENABLED" => "false" }).warning).to be_nil
    end

    it "is nil under SECRET_KEY_BASE_DUMMY, where telemetry is skipped on purpose" do
      expect(config({ "SECRET_KEY_BASE_DUMMY" => "1" }).warning).to be_nil
    end
  end

  describe "#sentry?" do
    it "needs telemetry on and a SENTRY_DSN" do
      expect(config(named.merge("SENTRY_DSN" => "https://key@sentry.example/1"))).to be_sentry
      expect(config(named.merge("SENTRY_DSN" => ""))).not_to be_sentry
      expect(config(named.merge("SENTRY_DSN" => "https://key@sentry.example/1"), rails_env: "development")).not_to be_sentry
      expect(config({ "SENTRY_DSN" => "https://key@sentry.example/1" })).not_to be_sentry
    end
  end

  describe "#traces_sampler" do
    it "uses the default rate and skips the health check" do
      sampler = config.traces_sampler
      expect(sampler.call(env: { "PATH_INFO" => "/games" })).to eq(0.1)
      expect(sampler.call(env: { "PATH_INFO" => "/up" })).to eq(0.0)
      expect(sampler.call({})).to eq(0.1)
    end

    it "uses SENTRY_TRACES_SAMPLE_RATE when set" do
      expect(config({ "SENTRY_TRACES_SAMPLE_RATE" => "0.5" }).traces_sampler.call({})).to eq(0.5)
    end

    it "rejects a rate that is not a number" do
      expect { config({ "SENTRY_TRACES_SAMPLE_RATE" => "lots" }).traces_sampler }.to raise_error(ArgumentError)
    end
  end

  it "takes the release from KAMAL_VERSION" do
    expect(config({ "KAMAL_VERSION" => "abc123" }).release).to eq("abc123")
    expect(config.release).to be_nil
  end

  it "defaults the PostHog settings" do
    expect(config.posthog_key).to eq(described_class::DEFAULTS["POSTHOG_KEY"])
    expect(config.posthog_host).to eq("https://t.joaotorr.es")
    expect(config.posthog_ui_host).to eq("https://eu.posthog.com")
  end

  it "overrides the PostHog settings from ENV" do
    env = { "POSTHOG_KEY" => "phc_other", "POSTHOG_HOST" => "https://p.example", "POSTHOG_UI_HOST" => "https://us.posthog.com" }
    expect([config(env).posthog_key, config(env).posthog_host, config(env).posthog_ui_host])
      .to eq(["phc_other", "https://p.example", "https://us.posthog.com"])
  end
end
