# frozen_string_literal: true
require_relative "experiment/lib/opencode_generation_observation"
require "json"
require "digest"
require "fileutils"
require "time"

campaign = "/home/petert/llm_para_campaigns/20261017-192226-sol61-opencode-medium"
source = "/home/petert/llm_para_experiments/20261017-192226"
output = File.join(campaign, "pricing")
raise "Pricing context already retained" if File.exist?(output)
ids = File.readlines(File.join(campaign, "run-ids.txt"), chomp: true).reject(&:empty?).sort
raise "Unexpected source scope" unless ids.size == 220
records = ids.map do |id|
  observation = JSON.parse(File.read(File.join(campaign, "observations", "#{id}.json")))
  session_path = File.join(source, id, "opencode-session.txt")
  digest = Digest::SHA256.file(session_path).hexdigest
  raise "Native session changed" unless digest == observation.fetch("sha256").fetch("opencode-session.txt")
  session = JSON.parse(File.read(session_path))
  steps = session.fetch("messages").flat_map { |message| message.fetch("parts").select { |part| part.fetch("type") == "step-finish" } }
  raise "Duplicate request accounting" unless steps.map { |part| part.fetch("id") }.uniq.size == steps.size
  usage = steps.map { |part| OpenCodeGenerationObservation.normalize_usage(part.fetch("tokens")) }
  totals = usage.first.keys.to_h { |key| [key, usage.sum { |counts| counts.fetch(key) }] }
  raise "Native cumulative counters differ" unless totals == observation.fetch("token_counts")
  {
    "id" => id, "session_id" => observation.fetch("session_id"), "native_session_sha256" => digest,
    "request_count" => usage.size, "maximum_request_input_tokens" => usage.map { |counts| counts.fetch("input_tokens") }.max,
    "requests_above_272000_tokens" => usage.count { |counts| counts.fetch("input_tokens") > 272000 },
    "cache_write_input_tokens" => totals.fetch("cache_write_input_tokens"),
    "token_counts" => totals
  }
end
report = {
  "schema_version" => 1, "checked_at" => Time.now.utc.iso8601,
  "source_batch" => "20261017-192226", "source_commit" => "352c09d57e14ef93744aa8cc741ff52884079e5f",
  "programs" => records.size, "requests" => records.sum { |row| row.fetch("request_count") },
  "maximum_request_input_tokens" => records.map { |row| row.fetch("maximum_request_input_tokens") }.max,
  "requests_above_272000_tokens" => records.sum { |row| row.fetch("requests_above_272000_tokens") },
  "cache_write_input_tokens" => records.sum { |row| row.fetch("cache_write_input_tokens") },
  "method" => "Exact native step-finish counters, including compaction; input includes cache reads/writes, output includes reasoning. Every session digest and cumulative total matches the accepted generation observation.",
  "checker_sha256" => Digest::SHA256.file(__FILE__).hexdigest, "records" => records
}
raise "Short-context pricing requires separate handling" unless report.fetch("requests_above_272000_tokens").zero? && report.fetch("cache_write_input_tokens").zero?
FileUtils.mkdir_p(output)
File.write(File.join(output, "request-context-summary.json"), JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, output)
puts JSON.pretty_generate(report.except("records"))
