# frozen_string_literal: true
require_relative "experiment/lib/opencode_generation_observation"
require "json"
require "digest"
require "fileutils"
require "time"

campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
source = "/home/petert/llm_para_experiments/20261019-134042"
output = File.join(campaign, "pricing")
target = File.join(output, "request-context-summary.json")
raise "Pricing context already retained" if File.exist?(target)
ids = File.readlines(File.join(campaign, "run-ids.txt"), chomp: true).reject(&:empty?).sort
raise "Unexpected source scope" unless ids.size == 220
records = ids.map do |id|
  observation = JSON.parse(File.read(File.join(campaign, "observations", "#{id}.json")))
  session_path = File.join(source, id, "opencode-session.txt")
  digest = Digest::SHA256.file(session_path).hexdigest
  raise "Native session changed" unless digest == observation.fetch("sha256").fetch("opencode-session.txt")
  session = JSON.parse(File.read(session_path))
  steps = session.fetch("messages").flat_map { |message| message.fetch("parts").select { |part| part.fetch("type") == "step-finish" } }
  raise "Duplicate or absent request accounting" if steps.empty? || steps.map { |part| part.fetch("id") }.uniq.size != steps.size
  usage = steps.map { |part| OpenCodeGenerationObservation.normalize_usage(part.fetch("tokens")) }
  totals = usage.first.keys.to_h { |key| [key, usage.sum { |counts| counts.fetch(key) }] }
  raise "Native cumulative counters differ" unless totals == observation.fetch("token_counts")
  {
    "id" => id, "session_id" => observation.fetch("session_id"), "native_session_sha256" => digest,
    "usage_complete" => observation.fetch("usage_complete"),
    "request_count" => usage.size, "maximum_request_input_tokens" => usage.map { |counts| counts.fetch("input_tokens") }.max,
    "maximum_request_output_tokens" => usage.map { |counts| counts.fetch("output_tokens") }.max,
    "requests_above_272000_tokens" => usage.count { |counts| counts.fetch("input_tokens") > 272000 },
    "cache_write_input_tokens" => totals.fetch("cache_write_input_tokens"), "token_counts" => totals
  }
end
report = {
  "schema_version" => 2, "checked_at" => Time.now.utc.iso8601,
  "source_batch" => "20261019-134042", "source_commit" => "40ad0bc6da259d4584e75b8f23f43c77e9751b24",
  "programs" => records.size, "complete_programs" => records.count { |row| row.fetch("usage_complete") },
  "incomplete_programs" => records.count { |row| !row.fetch("usage_complete") },
  "requests" => records.sum { |row| row.fetch("request_count") },
  "maximum_request_input_tokens" => records.map { |row| row.fetch("maximum_request_input_tokens") }.max,
  "maximum_request_output_tokens" => records.map { |row| row.fetch("maximum_request_output_tokens") }.max,
  "requests_above_272000_tokens" => records.sum { |row| row.fetch("requests_above_272000_tokens") },
  "cache_write_input_tokens" => records.sum { |row| row.fetch("cache_write_input_tokens") },
  "pricing_context_policy" => "flat_context", "input_limit_tokens" => 1_000_000,
  "method" => "Exact native completed-request step-finish counters, including compaction; input includes cache and output includes reasoning. All session digests and cumulative totals match retained observations. Interrupted sessions are explicit lower bounds, never complete task costs. The 272000-token count is descriptive only; this model has no context-dependent rate tier.",
  "checker_sha256" => Digest::SHA256.file(__FILE__).hexdigest, "records" => records
}
raise "Unexpected usage completeness" unless report.values_at("complete_programs", "incomplete_programs") == [217, 3]
raise "Unexpected native context or cache writes" unless report.fetch("maximum_request_input_tokens") <= 1_000_000 && report.fetch("cache_write_input_tokens").zero?
FileUtils.mkdir_p(output)
File.write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, output)
puts JSON.pretty_generate(report.except("records"))
