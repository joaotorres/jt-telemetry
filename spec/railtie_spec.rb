require "spec_helper"
require "rails"
require "action_controller/railtie"
require "jt_telemetry/railtie"

class RailtieSpecController < ActionController::Base
  def boom
    error = RuntimeError.new("boom")
    Rails.error.report(error)
    raise error
  end
end

# Boots one minimal app with telemetry on. Sentry keeps the Railtie's settings
# and only swaps its transport for DummyTransport, so nothing leaves the machine.
RSpec.describe JtTelemetry::Railtie do
  before(:all) do
    env = { "TELEMETRY_ENABLED" => "true", "APP_NAME" => "spec", "SENTRY_DSN" => "https://public@o0.ingest.de.sentry.io/1" }
    saved = ENV.to_h.slice(*env.keys)
    ENV.update(env)
    test_transport = proc do
      transport.transport_class = Sentry::DummyTransport
      self.background_worker_threads = 0
    end
    Sentry::Configuration.after(:configured, &test_transport)

    Class.new(Rails::Application) do
      config.root = __dir__
      config.eager_load = false
      config.logger = Logger.new(File::NULL)
      config.secret_key_base = "x" * 64
      config.hosts.clear
      routes.append { get "/boom" => "railtie_spec#boom" }
    end.initialize!
  ensure
    Sentry::Configuration.callbacks[:configured][:after].delete(test_transport)
    env&.each_key { |name| saved.key?(name) ? ENV[name] = saved[name] : ENV.delete(name) }
  end

  after(:all) { Sentry.close }

  before { events.clear }

  def events = Sentry.get_current_client.transport.events

  # Requests may also send a sampled transaction; only error events count here.
  def errors = events.grep(Sentry::ErrorEvent)

  it "configures Sentry" do
    sentry = Sentry.configuration
    expect(sentry.environment).to eq(Rails.env)
    expect(sentry.send_default_pii).to be(false)
    expect(sentry.before_send).not_to be_nil
    expect(sentry.before_send_transaction).not_to be_nil
    expect(sentry.rails.register_error_subscriber).to be(true)
  end

  it "sends Rails.error.report to Sentry once" do
    Rails.error.report(RuntimeError.new("x"))

    expect(errors.size).to eq(1)
  end

  it "sends an exception reported through Rails.error and raised in a request once" do
    status, = Rails.application.call(Rack::MockRequest.env_for("/boom"))

    expect(status).to eq(500)
    expect(errors.size).to eq(1)
  end
end
