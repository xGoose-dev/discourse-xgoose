# frozen_string_literal: true
require "rails_helper"
RSpec.describe DiscourseXgoose::Transcript do
  let(:call) { Struct.new(:turn_id, :status, :response_message).new("turn", "completed", { "finish_reason" => "stop", "tool_calls" => [] }) }
  let(:event) { Struct.new(:turn_id, :sequence, :kind, :payload).new("turn", 0, "turn_end", { "client_logs_complete" => true }) }
  it "requires a terminal event for every turn, not just a previous one" do
    expect(described_class.complete?([call], [event])).to eq(true)
    second = call.dup
    second.turn_id = "new-turn"
    expect(described_class.complete?([call, second], [event])).to eq(false)
  end
  it "marks missing sequences, tool results, and failed uploads incomplete" do
    event.sequence = 1
    expect(described_class.complete?([call], [event])).to eq(false)
    event.sequence = 0
    event.payload["client_logs_complete"] = false
    expect(described_class.complete?([call], [event])).to eq(false)
    event.payload["client_logs_complete"] = true
    call.response_message["tool_calls"] = [{ "id" => "missing-tool" }]
    expect(described_class.complete?([call], [event])).to eq(false)
  end
end
