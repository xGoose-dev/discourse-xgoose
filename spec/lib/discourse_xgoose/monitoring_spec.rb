# frozen_string_literal: true
require "rails_helper"
RSpec.describe "xGoose monitoring and budgets" do
  fab!(:user)
  fab!(:admin)
  fab!(:other_admin, :admin)
  let!(:session) { DiscourseXgoose::Session.create!(user_id: user.id) }
  def reserve(purpose = "generation")
    DiscourseXgoose::Quota.reserve!(
      user,
      session,
      SecureRandom.uuid,
      SecureRandom.uuid,
      { model: "mock", messages: [{ role: "user", content: "question" }], xgoose_purpose: purpose },
      100,
    )
  end
  def change(kind, amount, operation = SecureRandom.uuid, actor = admin)
    DiscourseXgoose::Budget.change!(
      actor,
      user,
      {
        kind: kind,
        amount_usd: amount,
        operation_id: operation,
        reason: "Testing budget management",
      },
    )
  end
  before do
    SiteSetting.xgoose_daily_budget_usd = 2
    SiteSetting.xgoose_input_usd_per_million = 1
    SiteSetting.xgoose_output_usd_per_million = 1
  end
  it "sets a personal limit, blocks zero, and returns to the site default" do
    change("daily", "0")
    expect { reserve }.to raise_error(DiscourseXgoose::Error, "quota_exceeded")
    change("daily", "3.25")
    expect(DiscourseXgoose::Quota.snapshot(user)).to include(
      limit_usd: 3.25,
      personal_limit_usd: 3.25,
    )
    change("daily", nil)
    expect(DiscourseXgoose::Quota.snapshot(user)).to include(limit_usd: 2, personal_limit_usd: nil)
  end
  it "sets today's total bonus idempotently and audits the administrator and reason" do
    id = SecureRandom.uuid
    2.times { change("bonus", "1.5", id) }
    expect(DiscourseXgoose::Quota.snapshot(user)).to include(limit_usd: 3.5, bonus_usd: 1.5)
    expect(DiscourseXgoose::BudgetChange.count).to eq(1)
    record = DiscourseXgoose::BudgetChange.last
    expect(record.admin_id).to eq(admin.id)
    expect(record.after_values["bonus_microusd"]).to eq(1_500_000)
    freeze_time 1.day.from_now do
      expect(DiscourseXgoose::Quota.snapshot(user)).to include(limit_usd: 2, bonus_usd: 0)
    end
  end
  it "cannot withdraw used or reserved bonus funds, and lowering the base does not refund" do
    change("daily", "0")
    change("bonus", "0.001")
    request = reserve
    expect { change("bonus", "0") }.to raise_error(Discourse::InvalidParameters)
    change("bonus", "0.0001")
    DiscourseXgoose::Quota.settle!(request, tokens: 50)
    expect { change("bonus", "0") }.to raise_error(Discourse::InvalidParameters)
    change("bonus", "0.00005")
    expect(DiscourseXgoose::Quota.snapshot(user)[:remaining_usd]).to eq(0)
    expect(DiscourseXgoose::Quota.snapshot(user)[:used_usd]).to eq(0.00005)
  end
  it "rejects invalid money and empty reasons without recording a change" do
    %w[NaN Infinity -1 1001 0.0000001 nope].each do |value|
      expect { change("daily", value) }.to raise_error(Discourse::InvalidParameters)
    end
    expect {
      DiscourseXgoose::Budget.change!(
        admin,
        user,
        { operation_id: SecureRandom.uuid, kind: "daily", amount_usd: 3, reason: " " },
      )
    }.to raise_error(Discourse::InvalidParameters)
    expect(DiscourseXgoose::BudgetChange.count).to eq(0)
  end
  it "retains a single metric after transcript deletion, preserving prices and missing latency" do
    request = reserve("summary")
    DiscourseXgoose::Quota.settle!(
      request,
      usage: {
        "prompt_tokens" => 80,
        "completion_tokens" => 20,
        "prompt_tokens_details" => {
          "cached_tokens" => 30,
        },
      },
      duration: 250,
      first_token_ms: 40,
      upstream_status: 200,
    )
    DiscourseXgoose::Quota.settle!(request, tokens: 999)
    session.destroy!
    metric = DiscourseXgoose::Metric.last
    expect(metric).to have_attributes(
      purpose: "summary",
      charged_microusd: 100 - 30 + 1,
      first_token_ms: 40,
      input_tokens: 80,
      output_tokens: 20,
      cache_tokens: 30,
      upstream_status: 200,
    )
    expect(DiscourseXgoose::Metric.count).to eq(1)
    expect(DiscourseXgoose::Quota.snapshot(user)[:used]).to eq(100)
  end
  it "aggregates historical cost and percentiles, independently of current rates" do
    request = reserve
    DiscourseXgoose::Quota.settle!(
      request,
      usage: {
        "prompt_tokens" => 80,
        "completion_tokens" => 20,
      },
      duration: 200,
      first_token_ms: 40,
    )
    second = reserve("summary")
    DiscourseXgoose::Quota.settle!(
      second,
      status: "failed",
      error: "upstream_timeout",
      duration: 400,
    )
    DiscourseXgoose::Rejection.create!(
      user_id: user.id,
      session_id: session.id,
      model: "mock",
      reason: "quota_exceeded",
      created_at: Time.current,
    )
    SiteSetting.xgoose_input_usd_per_million = 20
    report = DiscourseXgoose::Report.new({ timezone: "America/Chicago" }).overview
    expect(report[:summary]).to include(
      "cost" => 200,
      "estimated_cost" => 100,
      "calls" => 2,
      "failed" => 1,
      "summaries" => 1,
      "rejected" => 1,
      "duration_p50" => 300.0,
      "first_token_p50" => 40.0,
      "failure_rate" => 0.5,
    )
    expect(report[:series].sum { |r| r["cost"].to_i }).to eq(200)
    expect(report[:series].sum { |r| r["rejected"].to_i }).to eq(1)
    expect(report[:users].first[:today][:used]).to eq(200)
  end
  it "finds a user who has never used xGoose and rejects malformed filters" do
    expect(
      DiscourseXgoose::Report.new({ search: admin.username }).users[:users].map { |r| r[:id] },
    ).to include(admin.id)
    [
      { timezone: "invalid" },
      { start_date: "broken" },
      { start_date: "2020-01-01" },
      { status: "unknown" },
    ].each do |params|
      expect { DiscourseXgoose::Report.new(params) }.to raise_error(Discourse::InvalidParameters)
    end
  end
  it "cleans expired data while retaining active requests and effective budgets" do
    SiteSetting.xgoose_log_retention_days = 90
    change("daily", "3")
    request = reserve
    DiscourseXgoose::Quota.settle!(request, tokens: 50)
    DiscourseXgoose::Metric.update_all(created_at: 91.days.ago)
    DiscourseXgoose::BudgetChange.update_all(created_at: 91.days.ago)
    session.update_columns(created_at: 91.days.ago, updated_at: 91.days.ago)
    active_session =
      DiscourseXgoose::Session.create!(
        user_id: user.id,
        created_at: 91.days.ago,
        updated_at: 91.days.ago,
      )
    DiscourseXgoose::Quota.reserve!(
      user,
      active_session,
      SecureRandom.uuid,
      SecureRandom.uuid,
      { model: "mock", messages: [] },
      100,
    )
    Jobs::XgooseCleanup.new.execute({})
    expect(DiscourseXgoose::Session.exists?(session.id)).to eq(false)
    expect(DiscourseXgoose::Session.exists?(active_session.id)).to eq(true)
    expect(DiscourseXgoose::BudgetChange.count).to eq(0)
    expect(DiscourseXgoose::Budget.find_by(user_id: user.id).daily_microusd).to eq(3_000_000)
    expect(DiscourseXgoose::Metric.count).to eq(1)
    expect(PluginStore.get("discourse-xgoose", "cleanup_at")).to be_present
  end
  it "rechecks legacy completeness and protects unexpired metrics during retention cleanup" do
    request = reserve
    request.update_columns(created_at: 91.days.ago)
    DiscourseXgoose::Metric.capture!(request)
    session.update_columns(integrity_reasons: ["legacy_unchecked"])
    Jobs::XgooseCleanup.new.execute({})
    expect(DiscourseXgoose::Metric.exists?(request_id: request.id)).to eq(true)
    expect(session.reload.integrity_reasons).to include("request_in_progress")
    expect(session.integrity_reasons).not_to include("legacy_unchecked")
  end
end
