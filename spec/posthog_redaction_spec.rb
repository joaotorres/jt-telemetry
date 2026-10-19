require "spec_helper"
require "open3"

# Runs the snippet's redaction (Tags::REDACT) in Node on events shaped as
# posthog-js hands them to before_send.
RSpec.describe "PostHog redaction" do
  before { skip "needs node" unless system("node", "--version", out: File::NULL, err: File::NULL) }

  let(:token) { "aB3dE5gH7jK9mN1pQ3sT5vX7" }

  def run(js)
    sources = JtTelemetry::Redactor.new(["/invite/:token"]).sources
    out, status = Open3.capture2("node", "-e", <<~JS)
      const options = (#{JtTelemetry::Tags::REDACT})(#{JSON.generate(sources)});
      const result = (() => { #{js} })();
      console.log(JSON.stringify(result));
    JS
    expect(status).to be_success
    JSON.parse(out)
  end

  it "replaces the token in every URL property, nested ones included" do
    event = {
      event: "$pageview",
      properties: {
        "$current_url" => "https://done.joaotorr.es/invite/#{token}?x=1",
        "$pathname" => "/invite/#{token}",
        "$referrer" => "https://done.joaotorr.es/invite/#{token}",
        "$initial_current_url" => "https://done.joaotorr.es/invite/#{token}",
        "$elements" => [{ "attr__href" => "/invite/#{token}" }],
        "$snapshot_data" => [{ "type" => 4, "data" => { "href" => "https://done.joaotorr.es/invite/#{token}" } }],
        "count" => 3
      },
      "$set_once" => { "$initial_pathname" => "/invite/#{token}" }
    }
    sent = run("return options.before_send(#{JSON.generate(event)})")

    expect(JSON.generate(sent)).not_to include(token)
    expect(sent["properties"]["$current_url"]).to eq("https://done.joaotorr.es/invite/:token?x=1")
    expect(sent["properties"]["$pathname"]).to eq("/invite/:token")
    expect(sent["properties"]["$snapshot_data"].first["data"]["href"]).to eq("https://done.joaotorr.es/invite/:token")
    expect(sent["properties"]["count"]).to eq(3)
    expect(sent["$set_once"]["$initial_pathname"]).to eq("/invite/:token")
  end

  it "passes a dropped event through" do
    expect(run("return options.before_send(null)")).to be_nil
  end

  it "leaves compressed replay data alone" do
    js = <<~JS
      const data = new Uint8Array([1, 2, 3]);
      const sent = options.before_send({ properties: { $snapshot_data: data } });
      return sent.properties.$snapshot_data === data;
    JS
    expect(run(js)).to be(true)
  end

  it "masks the URLs session replay records" do
    request = { name: "https://done.joaotorr.es/invites/x/redeem and https://done.joaotorr.es/invite/#{token}" }
    sent = run("return options.session_recording.maskCapturedNetworkRequestFn(#{JSON.generate(request)})")
    expect(sent["name"]).to eq("https://done.joaotorr.es/invites/x/redeem and https://done.joaotorr.es/invite/:token")
  end
end
