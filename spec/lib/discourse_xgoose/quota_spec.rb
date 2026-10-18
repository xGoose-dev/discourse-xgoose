# frozen_string_literal: true
require "rails_helper"
RSpec.describe DiscourseXgoose::Quota do
  fab!(:user)
  let!(:session) { DiscourseXgoose::Session.create!(user_id: user.id) }
  let(:body) { { model: "test-model", messages: [{ role: "user", content: "Hello" }] } }
  def reserve(amount = 500)
    described_class.reserve!(user, session, SecureRandom.uuid, SecureRandom.uuid, body, amount)
  end
  before { SiteSetting.xgoose_daily_tokens = 1000 }
  it "reserves before dispatch, blocks overspending, and settles idempotently" do
    request = reserve(700)
    expect { reserve(400) }.to raise_error(DiscourseXgoose::Error, "quota_exceeded")
    described_class.settle!(request, tokens: 100)
    described_class.settle!(request, tokens: 100)
    expect(described_class.snapshot(user)).to include(used: 100, reserved: 0, remaining: 900)
  end
  it "charges the reservation when usage is missing or the process dies" do
    request = reserve
    request.update!(expires_at: 1.minute.ago)
    described_class.reap!
    expect(request.reload).to have_attributes(status: "interrupted", estimated: true, charged_tokens: 500)
    expect(described_class.snapshot(user)[:remaining]).to eq(500)
  end
  it "does not charge or reserve twice for a repeated request ID" do
    id = SecureRandom.uuid
    described_class.reserve!(user, session, id, SecureRandom.uuid, body, 100)
    expect { described_class.reserve!(user, session, id, SecureRandom.uuid, body, 100) }.to raise_error(DiscourseXgoose::Error, "duplicate_request")
    expect(described_class.snapshot(user)[:reserved]).to eq(100)
  end
  it "separates UTC calendar days and returns a UTC reset timestamp" do
    DiscourseXgoose::Usage.create!(user_id: user.id, day: Time.now.utc.to_date - 1, used: 1000)
    expect(described_class.snapshot(user)[:remaining]).to eq(1000)
    expect(Time.iso8601(described_class.snapshot(user)[:resets_at]).hour).to eq(0)
  end
end
