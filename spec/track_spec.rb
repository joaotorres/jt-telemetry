require "spec_helper"
require "open3"

# Runs the jtTrack script in Node against a fake posthog that prints the
# arguments capture gets.
RSpec.describe "jtTrack" do
  before { skip "needs node" unless system("node", "--version", out: File::NULL, err: File::NULL) }

  def captured(call)
    script = <<~JS
      const window = { posthog: { capture: (...args) => console.log(JSON.stringify(args)) } };
      (function () {
      #{JtTelemetry::Tags::TRACK}
      })();
      #{call}
    JS
    out, status = Open3.capture2("node", "-e", script)
    expect(status).to be_success
    JSON.parse(out)
  end

  it "batches an event as usual" do
    expect(captured(%(window.jtTrack("game_created", { players: 4 })))).to eq(["game_created", { "players" => 4 }, nil])
  end

  it "sends at once with sendBeacon when asked for a beacon" do
    expect(captured(%(window.jtTrack("pass_exported", {}, { beacon: true }))))
      .to eq(["pass_exported", {}, { "transport" => "sendBeacon", "send_instantly" => true }])
  end

  it "ignores other options" do
    expect(captured(%(window.jtTrack("game_created", {}, { beacon: false })))).to eq(["game_created", {}, nil])
  end
end
