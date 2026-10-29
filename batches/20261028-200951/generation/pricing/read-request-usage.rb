# frozen_string_literal: true
require "json"
require "digest"
require "/tmp/terra61-codex-generation-20261028-11909-fhjtv7/experiment/lib/codex_usage"

module TerraRequestUsage
  module_function

  def recover(record, sessions_root:)
    CodexUsage.validate_record!(record)
    raise "Unexpected campaign" unless record.fetch("batch") == "20261028-200951" && record.fetch("run_id").include?("_gpt-6.1-terra-medium_")
    path = File.join(sessions_root, record.fetch("session_path"))
    expected_fields = record.fetch("usage").keys.sort
    counters = lambda do |value|
      selected = value.slice(*CodexUsage::FIELDS)
      CodexUsage.validate_usage!(selected)
      raise "Missing per-response counters; do not substitute zero" unless selected.keys.sort == expected_fields
      selected
    end
    signature = ->(usage) { expected_fields.map { |field| usage.fetch(field) } }
    totals = expected_fields.to_h { |field| [field, 0] }
    prefixes = { signature.call(totals) => [totals.dup] }
    seen = {}
    requests = []
    token_count_snapshots = []
    windows = []
    duplicate_count = 0
    final_task_event = nil
    digest = Digest::SHA256.new
    File.foreach(path).with_index(1) do |line, number|
      digest.update(line)
      event = JSON.parse(line)
      payload = event.fetch("payload")
      if number == 1
        raise "Session identity differs" unless event.fetch("type") == "session_meta" &&
          payload.values_at("id", "cwd", "cli_version") == record.values_at("session_id", "session_cwd", "cli_version")
      end
      if event.fetch("type") == "token_usage_record"
        response_id = payload.fetch("response_id")
        raise "Missing native response identity" unless response_id.is_a?(String) && !response_id.empty?
        usage = counters.call(payload.fetch("usage"))
        cumulative = counters.call(payload.fetch("thread_token_usage"))
        fingerprint = [usage, cumulative]
        if seen.key?(response_id)
          raise "Conflicting duplicate native response" unless seen.fetch(response_id) == fingerprint
          duplicate_count += 1
          next
        end
        seen[response_id] = fingerprint
        expected_fields.each { |field| totals[field] += usage.fetch(field) }
        raise "Per-response sum differs from native cumulative usage" unless totals == cumulative
        (prefixes[signature.call(totals)] ||= []) << usage
        requests << { "response_id_sha256" => Digest::SHA256.hexdigest(response_id),
          "timestamp" => event.fetch("timestamp"), "usage" => usage }
      elsif event.fetch("type") == "event_msg"
        kind = payload["type"]
        final_task_event = kind if %w[task_started task_complete task_aborted turn_aborted task_failed].include?(kind)
        if kind == "token_count" && payload["info"]
          info = payload.fetch("info")
          token_count_snapshots << [counters.call(info.fetch("total_token_usage")), counters.call(info.fetch("last_token_usage"))]
          windows << info["model_context_window"] if info["model_context_window"].is_a?(Integer)
        end
      end
    end
    raise "Bound native session changed" unless digest.hexdigest == record.fetch("session_sha256")
    raise "Native task did not finish" unless final_task_event == "task_complete"
    raise "No native per-response usage" if requests.empty?
    raise "Per-response totals disagree with exact final record" unless totals == record.fetch("usage")
    raise "No independent token-count stream" if token_count_snapshots.empty?
    token_count_snapshots.each do |cumulative, last|
      raise "Native token-count stream disagrees" unless prefixes.fetch(signature.call(cumulative), []).include?(last)
    end
    raise "Final token-count stream differs" unless token_count_snapshots.last.first == totals
    { "schema_version" => 1, "source" => "codex_native_token_usage_record",
      "batch" => record.fetch("batch"), "run_id" => record.fetch("run_id"),
      "session_id" => record.fetch("session_id"), "session_sha256" => record.fetch("session_sha256"),
      "exact_final_record_sha256" => Digest::SHA256.hexdigest(JSON.generate(record)),
      "request_count" => requests.size, "duplicate_records_ignored" => duplicate_count,
      "token_count_snapshots_verified" => token_count_snapshots.size,
      "max_request_input_tokens" => requests.map { |row| row.fetch("usage").fetch("input_tokens") }.max,
      "model_context_windows" => windows.uniq.sort, "total_usage" => totals, "requests" => requests }
  end
end

if $PROGRAM_NAME == __FILE__
  records = JSON.parse($stdin.read)
  raise "Invalid scoped input" unless records.is_a?(Array) && records.size.between?(1, 220) &&
    records.map { |row| row.fetch("run_id") }.uniq.size == records.size
  records.each do |record|
    puts JSON.generate(TerraRequestUsage.recover(record, sessions_root: "/home/llmtest/.codex/sessions"))
  end
end
