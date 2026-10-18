# frozen_string_literal: true
module DiscourseXgoose
  class Transcript
    def self.complete?(requests, events)
      requests = requests.to_a
      events = events.to_a
      return false if requests.empty? || requests.any? { |r| r.status != "completed" }
      sequences = events.map(&:sequence).sort
      return false unless sequences == (0...sequences.length).to_a
      requests
        .group_by(&:turn_id)
        .all? do |turn_id, calls|
          turn_events = events.select { |e| e.turn_id == turn_id }
          terminal = turn_events.find { |e| e.kind == "turn_end" }
          next false unless terminal && terminal.payload["client_logs_complete"] == true
          next false unless calls.last.response_message["finish_reason"] == "stop"
          requested_tools =
            calls.flat_map do |r|
              Array(r.response_message["tool_calls"]).compact.map { |t| t["id"] }
            end
          finished_tools =
            turn_events.select { |e| e.kind == "tool_end" }.map { |e| e.payload["id"] }
          (requested_tools - finished_tools).empty?
        end
    end
  end
end
