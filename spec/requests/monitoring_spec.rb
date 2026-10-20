# frozen_string_literal: true
require "rails_helper"
RSpec.describe "xGoose admin monitoring endpoints" do
  fab!(:user)
  fab!(:admin)
  fab!(:moderator)
  let(:root) { "/admin/plugins/discourse-xgoose" }
  let(:headers) do
    { "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest", "HTTP_ORIGIN" => Discourse.base_url }
  end
  before { SiteSetting.xgoose_enabled = true }
  it "denies ordinary users and moderators, including budget mutations" do
    [user, moderator].each do |actor|
      sign_in(actor)
      %w[overview users sessions rejections].each do |action|
        get "#{root}/#{action}.json", headers: headers
        expect(response.status).not_to eq(200)
      end
      put "#{root}/users/#{user.id}/budget.json",
          params: {
            kind: "daily",
            amount_usd: 9,
            reason: "Unauthorized",
            operation_id: SecureRandom.uuid,
          },
          headers: headers
      expect(response.status).not_to eq(200)
    end
    expect(DiscourseXgoose::BudgetChange.count).to eq(0)
  end
  it "serves admin reports even when chat is disabled and validates filters" do
    SiteSetting.xgoose_enabled = false
    sign_in(admin)
    %w[overview users sessions rejections].each do |action|
      get "#{root}/#{action}.json", headers: headers
      expect(response.status).to eq(200)
    end
    get "#{root}/overview.json", params: { timezone: "invalid" }, headers: headers
    expect(response.status).to eq(400)
  end
  it "changes budgets with an audit trail and requires same origin" do
    sign_in(admin)
    values = {
      kind: "daily",
      amount_usd: "4.25",
      reason: "Community research",
      operation_id: SecureRandom.uuid,
    }
    put "#{root}/users/#{user.id}/budget.json",
        params: values,
        headers: headers.merge("HTTP_ORIGIN" => "https://bad.example")
    expect(response.status).to eq(403)
    2.times do
      put "#{root}/users/#{user.id}/budget.json", params: values, headers: headers
      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("quota", "limit_usd")).to eq(4.25)
    end
    expect(DiscourseXgoose::BudgetChange.count).to eq(1)
    put "#{root}/users/#{user.id}/budget.json",
        params: values.merge(amount_usd: "", operation_id: SecureRandom.uuid),
        headers: headers
    expect(response.status).to eq(200)
    expect(response.parsed_body.dig("quota", "personal_limit_usd")).to eq(nil)
    get "#{root}/users/#{user.id}.json", headers: headers
    expect(response.status).to eq(200)
    expect(response.parsed_body["changes"].first["reason"]).to eq("Community research")
  end
  it "records quota rejections without request content or fake model usage" do
    SiteSetting.xgoose_api_base_url = "https://llm.example.com/v1"
    SiteSetting.xgoose_api_key = "test-secret"
    SiteSetting.xgoose_model = "test-model"
    DiscourseXgoose::Budget.create!(user_id: user.id, daily_microusd: 0)
    session = DiscourseXgoose::Session.create!(user_id: user.id)
    sign_in(user)
    post "/xgoose/sessions/#{session.id}/chat/completions",
         params: { messages: [{ role: "user", content: "secret body" }] }.to_json,
         headers:
           headers.merge(
             "CONTENT_TYPE" => "application/json",
             "HTTP_X_XGOOSE_REQUEST_ID" => SecureRandom.uuid,
             "HTTP_X_XGOOSE_TURN_ID" => SecureRandom.uuid,
           )
    expect(response.status).to eq(429)
    expect(DiscourseXgoose::Rejection.last.reason).to eq("quota_exceeded")
    expect(DiscourseXgoose::Rejection.last.attributes.to_s).not_to include("secret body")
    expect(DiscourseXgoose::Metric.count).to eq(0)
  end
  it "does not load message bodies in session lists and preserves legacy exports" do
    session = DiscourseXgoose::Session.create!(user_id: user.id)
    request =
      DiscourseXgoose::Quota.reserve!(
        user,
        session,
        SecureRandom.uuid,
        SecureRandom.uuid,
        { model: "mock", messages: [{ role: "user", content: "PRIVATE-SNAPSHOT" }] },
        100,
      )
    DiscourseXgoose::Quota.settle!(
      request,
      tokens: 50,
      response: {
        "content" => "answer",
        "finish_reason" => "stop",
      },
    )
    sign_in(admin)
    get "#{root}/sessions.json", headers: headers
    expect(response.status).to eq(200)
    expect(response.body).not_to include("PRIVATE-SNAPSHOT", "messages", "response_message")
    get "#{root}/sessions/#{session.id}.json", headers: headers
    expect(response.status).to eq(200)
    expect(response.parsed_body["timeline"].length).to eq(1)
    get "/admin/plugins/xgoose/#{session.id}.txt", headers: headers
    expect(response.status).to eq(200)
    expect(response.body).to include("PRIVATE-SNAPSHOT", "answer", "TURN")
    delete "#{root}/sessions/#{session.id}.json", headers: headers
    expect(response.status).to eq(200)
    expect(DiscourseXgoose::Metric.count).to eq(1)
  end
end
