require "spec_helper"

RSpec.describe JtTelemetry::Config do
  def config(env = {}, rails_env: "production")
    described_class.new(env:, rails_env:)
  end

  describe "#enabled?" do
    it "defaults to on in production and off elsewhere" do
      expect(config({}, rails_env: "production")).to be_enabled
      expect(config({}, rails_env: "development")).not_to be_enabled
      expect(config({}, rails_env: "test")).not_to be_enabled
    end

    it "follows TELEMETRY_ENABLED when set" do
      expect(config({ "TELEMETRY_ENABLED" => "false" }, rails_env: "production")).not_to be_enabled
      expect(config({ "TELEMETRY_ENABLED" => "true" }, rails_env: "development")).to be_enabled
      expect(config({ "TELEMETRY_ENABLED" => "1" }, rails_env: "development")).to be_enabled
    end

    it "treats a blank TELEMETRY_ENABLED as unset" do
      expect(config({ "TELEMETRY_ENABLED" => " " }, rails_env: "production")).to be_enabled
    end
  end

  describe "#validate!" do
    it "requires APP_NAME when enabled" do
      expect { config.validate! }.to raise_error(JtTelemetry::Error, /APP_NAME/)
      expect { config({ "APP_NAME" => "onset" }).validate! }.not_to raise_error
    end

    it "does not require APP_NAME when disabled" do
      expect { config({}, rails_env: "development").validate! }.not_to raise_error
    end
  end

  describe "#sentry?" do
    it "needs telemetry on and a SENTRY_DSN" do
      expect(config({ "SENTRY_DSN" => "https://key@sentry.example/1" })).to be_sentry
      expect(config({ "SENTRY_DSN" => "" })).not_to be_sentry
      expect(config({ "SENTRY_DSN" => "https://key@sentry.example/1" }, rails_env: "development")).not_to be_sentry
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
