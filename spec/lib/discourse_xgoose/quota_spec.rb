# frozen_string_literal: true
require "rails_helper"
RSpec.describe DiscourseXgoose::Quota do
  fab!(:user)
  let!(:session) { DiscourseXgoose::Session.create!(user_id: user.id) }
  let(:body) { { model: "test-model", messages: [{ role: "user", content: "Hello" }] } }
  def reserve(amount = 500)
    described_class.reserve!(user, session, SecureRandom.uuid, SecureRandom.uuid, body, amount)
  end
  before do
    SiteSetting.xgoose_daily_budget_usd = 0.001
    SiteSetting.xgoose_input_usd_per_million = 1.0
    SiteSetting.xgoose_output_usd_per_million = 1.0
  end
  it "reserves dollars atomically and settles idempotently using the request price snapshot" do
    request = reserve(700)
    expect { reserve(400) }.to raise_error(DiscourseXgoose::Error, "quota_exceeded")
    SiteSetting.xgoose_input_usd_per_million = 50.0
    described_class.settle!(request, usage: { "prompt_tokens" => 80, "completion_tokens" => 20 })
    described_class.settle!(request, tokens: 999)
    expect(described_class.snapshot(user)).to include(used: 100, reserved: 0, remaining_usd: 0.0009)
    expect(request.reload.charged_microusd).to eq(100)
  end
  it "charges the dollar reservation when usage is missing or the process dies" do
    request = reserve
    request.update!(expires_at: 1.minute.ago)
    described_class.reap!
    expect(request.reload).to have_attributes(
      status: "interrupted",
      estimated: true,
      charged_tokens: 500,
      charged_microusd: 500,
    )
    expect(described_class.snapshot(user)[:remaining_usd]).to eq(0.0005)
  end
  it "does not charge or reserve twice for a repeated request ID" do
    id = SecureRandom.uuid
    described_class.reserve!(user, session, id, SecureRandom.uuid, body, 100)
    expect {
      described_class.reserve!(user, session, id, SecureRandom.uuid, body, 100)
    }.to raise_error(DiscourseXgoose::Error, "duplicate_request")
    expect(described_class.snapshot(user)).to include(reserved: 100, reserved_usd: 0.0001)
  end
  it "separates UTC calendar days and returns a UTC reset timestamp" do
    DiscourseXgoose::Usage.create!(
      user_id: user.id,
      day: Time.now.utc.to_date - 1,
      used_microusd: 1000,
    )
    expect(described_class.snapshot(user)[:remaining_usd]).to eq(0.001)
    expect(Time.iso8601(described_class.snapshot(user)[:resets_at]).hour).to eq(0)
  end
  it "prices cache reads without double-counting input, rounding once to micro-USD" do
    rates = {
      "input" => "0.1",
      "output" => "0.5",
      "cache_read" => "0.01",
      "cache_write" => "0.125",
    }
    usage = {
      "prompt_tokens" => 1000,
      "completion_tokens" => 100,
      "prompt_tokens_details" => {
        "cached_tokens" => 400,
        "cache_write_tokens" => 100,
      },
    }
    expect(DiscourseXgoose::Pricing.cost(usage, rates)).to eq(117)
  end
end
