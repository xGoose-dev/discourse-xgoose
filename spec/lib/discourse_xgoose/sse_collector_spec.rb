# frozen_string_literal: true
require "rails_helper"
RSpec.describe DiscourseXgoose::SseCollector do
  it "reconstructs UTF-8 and tool arguments across arbitrary byte boundaries" do
    collector = described_class.new
    data =
      [
        { choices: [{ delta: { content: "你好" } }] },
        {
          choices: [
            {
              delta: {
                tool_calls: [
                  {
                    index: 0,
                    id: "tool-1",
                    function: {
                      name: "search_forum",
                      arguments: '{"query":',
                    },
                  },
                ],
              },
            },
          ],
        },
        {
          choices: [
            {
              delta: {
                tool_calls: [{ index: 0, function: { arguments: '"hello"}' } }],
              },
              finish_reason: "tool_calls",
            },
          ],
        },
        { choices: [], usage: { prompt_tokens: 12, completion_tokens: 7 } },
      ].map { |e| "data: #{e.to_json}\r\n\r\n" }.join + "data: [DONE]"
    data.b.bytes.each_slice(3) { |bytes| collector.feed(bytes.pack("C*")) }
    collector.finish
    expect(collector.done).to eq(true)
    expect(collector.tokens).to eq(19)
    expect(collector.message["content"]).to eq("你好")
    expect(collector.message["tool_calls"][0]["function"]["arguments"]).to eq('{"query":"hello"}')
  end
  it "keeps partial content and identifies incomplete streams" do
    collector = described_class.new
    collector.feed("data: #{{ choices: [{ delta: { content: "Partial" } }] }.to_json}\n\n")
    expect(collector.message["content"]).to eq("Partial")
    expect(collector.done).to eq(false)
    expect(collector.tokens).to be_nil
  end
end
