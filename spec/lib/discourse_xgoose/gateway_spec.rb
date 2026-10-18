# frozen_string_literal: true
require "rails_helper"
RSpec.describe DiscourseXgoose::Gateway do
  fab!(:user)
  let!(:session) { DiscourseXgoose::Session.create!(user_id: user.id) }
  let(:body) { { model: "mock", messages: [{ role: "user", content: "Hello" }], stream: true } }
  let(:audit) do
    DiscourseXgoose::Quota.reserve!(user, session, SecureRandom.uuid, SecureRandom.uuid, body, 500)
  end
  before do
    SiteSetting.xgoose_api_base_url = "https://model.example/v1"
    SiteSetting.xgoose_api_key = "secret"
  end
  def stream(content)
    stub_request(:post, "https://model.example/v1/chat/completions").to_return(
      status: 200,
      body: content,
    )
    described_class.stream(audit, body) { |_chunk| }
  end
  it "charges conservatively when usage is missing" do
    stream(
      "data: #{{ choices: [{ delta: { content: "Hi" }, finish_reason: "stop" }] }.to_json}\n\ndata: [DONE]\n\n",
    )
    expect(audit.reload).to have_attributes(
      status: "completed",
      charged_tokens: 500,
      estimated: true,
    )
  end
  it "retains partial output and conservative accounting on premature EOF" do
    stream("data: #{{ choices: [{ delta: { content: "Partial" } }] }.to_json}\n\n")
    expect(audit.reload).to have_attributes(
      status: "failed",
      error_code: "upstream_incomplete",
      charged_tokens: 500,
    )
    expect(audit.response_message["content"]).to eq("Partial")
  end
  it "does not follow upstream redirects or expose their bodies" do
    stub_request(:post, "https://model.example/v1/chat/completions").to_return(
      status: 302,
      headers: {
        "Location" => "https://evil.example/",
      },
      body: "private upstream diagnostic",
    )
    chunks = []
    described_class.stream(audit, body) { |chunk| chunks << chunk }
    expect(audit.reload.error_code).to eq("upstream_http_302")
    expect(chunks.join).not_to include("private upstream diagnostic", "secret")
    expect(a_request(:get, "https://evil.example/")).not_to have_been_made
  end
  it "finalizes the reservation when a browser disconnects during output" do
    stub_request(:post, "https://model.example/v1/chat/completions").to_return(
      status: 200,
      body: "data: #{{ choices: [{ delta: { content: "Partial" } }] }.to_json}\n\n",
    )
    described_class.stream(audit, body) { |_chunk| raise IOError, "closed" }
    expect(audit.reload).to have_attributes(status: "interrupted", charged_tokens: 500)
    expect(DiscourseXgoose::Quota.snapshot(user)[:reserved]).to eq(0)
  end
end
