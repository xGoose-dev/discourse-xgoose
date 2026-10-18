# frozen_string_literal: true
require "rails_helper"
RSpec.describe "xGoose endpoints" do
  fab!(:user)
  fab!(:other_user, :user)
  fab!(:admin)
  fab!(:moderator)
  before do
    SiteSetting.xgoose_enabled = true
    SiteSetting.xgoose_api_base_url = "https://llm.example.com/v1"
    SiteSetting.xgoose_api_key = "secret-never-public"
    SiteSetting.xgoose_model = "test-model"
  end
  def origin
    { "HTTP_ORIGIN" => Discourse.base_url, "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest" }
  end
  def session_for(owner)
    DiscourseXgoose::Session.create!(user_id: owner.id)
  end
  it "requires login and never discloses upstream credentials" do
    get "/xgoose/config.json"
    expect(response.status).to eq(403)
    sign_in(user)
    get "/xgoose/config.json"
    expect(response.status).to eq(200)
    expect(response.body).not_to include("secret-never-public", "llm.example.com")
  end
  it "rejects cross-origin writes and other users' sessions" do
    sign_in(user)
    post "/xgoose/sessions.json", params: {}, headers: { "HTTP_ORIGIN" => "https://evil.example" }
    expect(response.status).to eq(403)
    session = session_for(other_user)
    post "/xgoose/sessions/#{session.id}/events.json", params: { events: [] }, headers: origin
    expect(response.status).to eq(404)
  end
  it "stores idempotent client events separately from server accounting" do
    sign_in(user)
    session = session_for(user)
    event = { event_id: SecureRandom.uuid, turn_id: SecureRandom.uuid, sequence: 0, kind: "tool_start", payload: { name: "search_forum" } }
    2.times do
      post "/xgoose/sessions/#{session.id}/events.json", params: { events: [event] }.to_json, headers: origin.merge("CONTENT_TYPE" => "application/json")
      expect(response.status).to eq(200)
    end
    expect(session.events.count).to eq(1)
    expect(DiscourseXgoose::Usage.count).to eq(0)
  end
  it "restricts logs to administrators and safely exports escaped source text" do
    session = session_for(user)
    sign_in(moderator)
    get "/admin/plugins/xgoose/#{session.id}.json"
    expect(response.status).not_to eq(200)
    sign_in(admin)
    get "/admin/plugins/xgoose/#{session.id}.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["complete"]).to eq(false)
    get "/admin/plugins/xgoose/#{session.id}"
    expect(response.status).to eq(200)
    expect(response.body).to include("Client-reported tool events")
  end
  it "streams a tool-capable completion and saves the final answer and usage" do
    sign_in(user)
    session = session_for(user)
    data = "data: #{ {choices: [{delta: {content: 'Answer'}, finish_reason: 'stop'}]}.to_json }\n\n" +
      "data: #{ {choices: [], usage: {prompt_tokens: 10, completion_tokens: 5}}.to_json }\n\n" + "data: [DONE]\n\n"
    stub_request(:post, "https://llm.example.com/v1/chat/completions").with(headers: { "Authorization" => "Bearer secret-never-public" }).to_return(status: 200, body: data, headers: { "Content-Type" => "text/event-stream" })
    post "/xgoose/sessions/#{session.id}/chat/completions", params: { messages: [{ role: "user", content: "Hello" }] }.to_json,
      headers: origin.merge("CONTENT_TYPE" => "application/json", "HTTP_X_XGOOSE_REQUEST_ID" => SecureRandom.uuid, "HTTP_X_XGOOSE_TURN_ID" => SecureRandom.uuid)
    expect(response.status).to eq(200)
    expect(response.body).to include("Answer", "[DONE]")
    expect(session.requests.last).to have_attributes(status: "completed", charged_tokens: 15, estimated: false)
    expect(session.requests.last.response_message["content"]).to eq("Answer")
  end
end
