require "spec_helper"
require "action_view"

RSpec.describe JtTelemetry::Helper do
  let(:view) do
    Class.new do
      include JtTelemetry::Helper
      attr_accessor :content_security_policy_nonce
    end.new
  end

  def render_with(env, rails_env: "production", nonce: nil)
    view.content_security_policy_nonce = nonce
    allow(JtTelemetry).to receive(:config).and_return(JtTelemetry::Config.new(env:, rails_env:))
    view.jt_telemetry_tags
  end

  context "when telemetry is enabled" do
    subject(:html) { render_with({ "APP_NAME" => "onset" }) }

    it "returns a single html_safe script tag" do
      expect(html).to be_html_safe
      expect(html.scan("<script").size).to eq(1)
    end

    it "loads PostHog through the proxy with the agreed options" do
      expect(html).to include("/static/array.js")
      expect(html).to include("posthog.init(\"#{JtTelemetry::Config::DEFAULTS["POSTHOG_KEY"]}\"")
      expect(html).to include(%("api_host":"https://t.joaotorr.es"))
      expect(html).to include(%("ui_host":"https://eu.posthog.com"))
      expect(html).to include(%("persistence":"memory"))
      expect(html).to include(%("person_profiles":"identified_only"))
      expect(html).to include(%("capture_pageview":"history_change"))
      expect(html).to include(%("capture_exceptions":true))
      expect(html).not_to include("cookieless_mode")
    end

    it "registers the app super property right after init" do
      expect(html).to match(/posthog\.init\([^\n]*\);\nposthog\.register\(\{"app":"onset"\}\);/)
    end

    it "guards against a second init and defines jtTrack" do
      expect(html).to include("if (window.jtTrack) return;")
      expect(html.index("if (window.jtTrack) return;")).to be < html.index("posthog.init")
      expect(html).to include("window.jtTrack = function (name, props, options)")
    end
  end

  it "adds the CSP nonce when there is one" do
    expect(render_with({ "APP_NAME" => "onset" }, nonce: "abc123")).to start_with(%(<script nonce="abc123">))
    expect(render_with({ "APP_NAME" => "onset" })).to start_with("<script>")
  end

  it "renders only the no-op jtTrack in production without APP_NAME" do
    html = render_with({}, rails_env: "production")
    expect(html).to include("window.jtTrack")
    expect(html).not_to include("posthog.init")
  end

  it "renders only the no-op jtTrack when telemetry is disabled" do
    html = render_with({}, rails_env: "development")
    expect(html).to include("window.jtTrack")
    expect(html).not_to include("posthog.init")
    expect(html).not_to include("array.js")
  end

  it "passes no redaction to PostHog without declared paths" do
    expect(render_with({ "APP_NAME" => "onset" })).not_to include("maskCapturedNetworkRequestFn")
  end

  it "passes the declared paths to PostHog's before_send and replay" do
    allow(JtTelemetry).to receive(:redact_paths).and_return(["/invite/:token"])
    html = render_with({ "APP_NAME" => "done" })
    expect(html).to include("before_send", "maskCapturedNetworkRequestFn")
    expect(html).to include(%([["/invite/[^/?#\\\\s\\"']+","/invite/:token"]]))
  end

  it "keeps ENV values from closing the script tag" do
    html = render_with({ "APP_NAME" => "</script><script>alert(1)" })
    expect(html.scan("</script>").size).to eq(1)
  end
end
