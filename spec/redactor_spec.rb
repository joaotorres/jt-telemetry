require "spec_helper"
require "sentry-ruby"
require "rack"

RSpec.describe JtTelemetry::Redactor do
  let(:token) { "x0RxayEJsw2ySUhAfHZv9nWS" }
  let(:redactor) { described_class.new(["/phone/:token"]) }

  describe "#redact" do
    it "replaces each segment with its name, up to the next slash, query or quote" do
      expect(redactor.redact("https://app.example/phone/#{token}")).to eq("https://app.example/phone/:token")
      expect(redactor.redact("/phone/#{token}/bundle.pkpasses")).to eq("/phone/:token/bundle.pkpasses")
      expect(redactor.redact("/phone/#{token}?a=1")).to eq("/phone/:token?a=1")
      expect(redactor.redact(%(No route matches [GET] "/phone/#{token}"))).to eq(%(No route matches [GET] "/phone/:token"))
    end

    it "handles several segments and several paths" do
      redactor = described_class.new(["/exports/:id/passes/:pass_id", "/invite/:identifier"])
      expect(redactor.redact("/exports/1/passes/2 and /invite/abc")).to eq("/exports/:id/passes/:pass_id and /invite/:identifier")
    end

    it "leaves other paths and non strings alone" do
      expect(redactor.redact("/phones/#{token}")).to eq("/phones/#{token}")
      expect(redactor.redact({ a: ["/up", 1, nil] })).to eq({ a: ["/up", 1, nil] })
    end
  end

  describe "as Sentry's before_send and before_send_transaction" do
    before do
      redactor = described_class.new(["/phone/:token"])
      Sentry.init do |sentry|
        sentry.dsn = "https://public@o0.ingest.de.sentry.io/1"
        sentry.transport.transport_class = Sentry::DummyTransport
        sentry.background_worker_threads = 0
        sentry.send_default_pii = false
        sentry.traces_sample_rate = 1.0
        sentry.before_send = redactor
        sentry.before_send_transaction = redactor
      end
    end

    after { Sentry.close }

    def sent = Sentry.get_current_client.transport.events.map { JSON.generate(_1.to_h) }

    def phone_request
      url = "https://app.example/phone/#{token}/bundle.pkpasses?ref=/phone/#{token}"
      Sentry.get_current_scope.set_rack_env(Rack::MockRequest.env_for(url, "HTTP_REFERER" => "https://app.example/phone/#{token}"))
      Sentry.add_breadcrumb(Sentry::Breadcrumb.new(message: "GET /phone/#{token}", data: { url: "/phone/#{token}" }))
    end

    it "redacts an error event: request, breadcrumbs, exception and transaction name" do
      phone_request
      Sentry.get_current_scope.set_transaction_name("/phone/#{token}", source: :url)
      Sentry.capture_exception(RuntimeError.new("failed on /phone/#{token}"))

      expect(sent.size).to eq(1)
      expect(sent.first).not_to include(token)
      expect(sent.first).to include("https://app.example/phone/:token/bundle.pkpasses")
    end

    it "redacts a transaction: request, name, span descriptions and span data" do
      phone_request
      transaction = Sentry.start_transaction(name: "/phone/#{token}", source: :url)
      Sentry.get_current_scope.set_span(transaction)
      transaction.with_child_span(op: "http.client", description: "GET https://app.example/phone/#{token}") do |span|
        span.set_data("path", "/phone/#{token}")
      end
      transaction.finish

      expect(sent.size).to eq(1)
      expect(sent.first).not_to include(token)
      expect(sent.first).to include(%("path":"/phone/:token"))
    end
  end
end
