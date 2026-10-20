# frozen_string_literal: true
module DiscourseXgoose
  class Transcript
    def self.reasons(requests, events)
      requests, events = requests.to_a, events.to_a
      reasons = []
      reasons << "no_requests" if requests.empty?
      reasons << "request_in_progress" if requests.any? { |r| r.status == "reserved" }
      reasons << "upstream_failed" if requests.any? { |r| r.status == "failed" }
      reasons << "interrupted" if requests.any? { |r| r.status == "interrupted" }
      sequences = events.map(&:sequence).sort
      reasons << "event_gap" unless sequences == (0...sequences.length).to_a
      requests
        .group_by(&:turn_id)
        .each do |turn, calls|
          reported = events.select { |e| e.turn_id == turn }
          terminal = reported.find { |e| e.kind == "turn_end" }
          unless terminal && terminal.payload["client_logs_complete"] == true
            reasons << "missing_client_events"
          end
          reasons << "partial_output" unless calls.last.response_message["finish_reason"] == "stop"
          requested =
            calls.flat_map do |r|
              Array(r.response_message["tool_calls"]).compact.map { |t| t["id"] }
            end
          finished = reported.select { |e| e.kind == "tool_end" }.map { |e| e.payload["id"] }
          reasons << "missing_tool_result" if (requested - finished).any?
        end
      reasons.uniq
    end
    def self.complete?(requests, events)
      reasons(requests, events).empty?
    end
    def self.refresh!(session)
      session.with_lock do
        requests = session.requests.order(:id).select(:id, :turn_id, :status, :response_message)
        events = session.events.order(:sequence, :id)
        errors = reasons(requests, events)
        session.update!(complete: errors.empty?, integrity_reasons: errors)
      end
    end
    def self.timeline(requests, events)
      requests
        .group_by(&:turn_id)
        .map do |turn, calls|
          client = events.select { |e| e.turn_id == turn }
          # The last user input on the first normal request is the current question.
          first =
            calls.find { |r| r.purpose == "generation" } ||
              calls.find { |r| r.purpose == "unknown" }
          question = first&.messages&.reverse&.find { |m| m["role"] == "user" }
          {
            turn_id: turn,
            question: question,
            charged_microusd: calls.sum(&:charged_microusd),
            tokens: calls.sum(&:charged_tokens),
            duration_ms: calls.sum { |r| r.duration_ms.to_i },
            reasons: reasons(calls, client).reject { |r| r == "event_gap" },
            steps:
              calls.map do |r|
                {
                  request_id: r.request_id,
                  purpose: r.purpose,
                  status: r.status,
                  response: r.response_message,
                  error_code: r.error_code,
                  tool_results:
                    client
                      .select do |e|
                        e.kind == "tool_end" &&
                          Array(r.response_message["tool_calls"]).compact.any? do |t|
                            t["id"] == e.payload["id"]
                          end
                      end
                      .map { |e| { source: "client_reported", payload: e.payload } },
                }
              end,
            client_events:
              client.map do |e|
                {
                  kind: e.kind,
                  sequence: e.sequence,
                  source: "client_reported",
                  payload: e.payload,
                }
              end,
          }
        end
    end
    def self.text(session, requests, events)
      lines = [
        "xGoose transcript",
        "Session: #{session.id}; user: #{session.user_id}",
        "Integrity: #{reasons(requests, events).join(", ").presence || "complete"}",
        "Client-reported events are untrusted. Image pixels are not stored.",
      ]
      timeline(requests, events).each do |turn|
        lines << "\nTURN #{turn[:turn_id]} — USD #{turn[:charged_microusd] / 1_000_000.0} — #{turn[:tokens]} tokens"
        lines << "user: #{JSON.generate(turn[:question])}"
        turn[:steps].each do |step|
          lines << "#{step[:purpose]} [#{step[:status]}] #{step[:request_id]}"
          lines << "assistant: #{JSON.generate(step[:response])}"
          step[:tool_results].each do |t|
            lines << "client_reported tool: #{JSON.generate(t[:payload])}"
          end
        end
        turn[:client_events].each do |e|
          lines << "client_reported #{e[:kind]}: #{JSON.generate(e[:payload])}"
        end
      end
      lines.join("\n")
    end
  end
end
