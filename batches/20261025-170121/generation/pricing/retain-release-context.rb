# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "time"

# Re-express already-retained exact accounting in the established flat-context
# release schema. No new counters, pricing decisions or model requests.
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium"
pricing = File.join(campaign, "pricing")
original_path = File.join(pricing, "request-context-summary.json")
original = JSON.parse(File.read(original_path))
usage_path = File.join(pricing, "request-usage.jsonl")
raise "Request accounting changed" unless Digest::SHA256.file(usage_path).hexdigest == original.fetch("request_usage_sha256")
usage = File.readlines(usage_path).map { |line| JSON.parse(line) }
ids = File.readlines(File.join(campaign, "run-ids.txt"), chomp: true).sort
raise "Context scope differs" unless usage.map { |row| row.fetch("id") }.sort == ids && ids.size == 220
records = usage.map do |record|
  observation = JSON.parse(File.read(File.join(campaign, "observations", record.fetch("id") + ".json")))
  raise "Unexpected model or profile" unless observation.fetch("model") == "opencode-go/beam-free" && record.fetch("profile") == "beam-1.0-oc-medium"
  raise "Context source identity changed" unless record.fetch("batch") == original.fetch("source_batch") && record.fetch("source_commit") == original.fetch("source_commit")
  raise "Native context provenance changed" unless record.fetch("session_id") == observation.fetch("session_id") &&
    record.fetch("native_session_sha256") == observation.fetch("sha256").fetch("opencode-session.txt") &&
    record.fetch("token_counts") == observation.fetch("token_counts") && record.fetch("usage_complete") == observation.fetch("usage_complete")
  maximum = record.fetch("max_request_input_tokens")
  raise "Cannot infer long-request count from these maxima" unless maximum.positive? && maximum <= 272000
  raise "Cache-write policy changed" unless record.fetch("token_counts").fetch("cache_write_input_tokens").zero?
  { "id" => record.fetch("id"), "session_id" => record.fetch("session_id"),
    "native_session_sha256" => record.fetch("native_session_sha256"), "token_counts" => record.fetch("token_counts"),
    "request_count" => record.fetch("requests"), "maximum_request_input_tokens" => maximum,
    "requests_above_272000_tokens" => 0, "cache_write_input_tokens" => 0,
    "usage_complete" => record.fetch("usage_complete") }
end
raise "Context totals changed" unless records.sum { |record| record.fetch("request_count") } == original.fetch("requests_with_exact_counters") &&
  records.map { |record| record.fetch("maximum_request_input_tokens") }.max == original.fetch("maximum_request_input_tokens")
normalized = original.merge("schema_version" => 2, "pricing_context_policy" => "flat_context", "input_limit_tokens" => 1_048_576,
  "requests" => original.fetch("requests_with_exact_counters"), "requests_above_272000_tokens" => 0,
  "cache_write_input_tokens" => 0, "records" => records,
  "normalized_at" => Time.now.utc.iso8601, "source_summary_sha256" => Digest::SHA256.file(original_path).hexdigest,
  "normalization_checker_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
  "normalization_policy" => "Schema adaptation only; original request summary retained unchanged. Per-program exact counters and maxima bind to native sessions. The maximum request is below 272000, proving zero requests above that threshold. Model-advertised context limit remains1048576; flat comparison rates and partial-usage policy are unchanged.")
target = File.join(pricing, "request-context-verification.json")
File.write(target, JSON.pretty_generate(normalized) + "\n", mode: "wx")
FileUtils.cp(__FILE__, pricing)
puts JSON.pretty_generate({ "output" => target, "sha256" => Digest::SHA256.file(target).hexdigest,
  "programs" => records.size, "requests" => normalized.fetch("requests"), "complete" => normalized.fetch("complete_programs"),
  "partial" => normalized.fetch("incomplete_programs"), "original_summary_unchanged" => true })
