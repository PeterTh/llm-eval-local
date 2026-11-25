# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "shellwords"
require "time"

root = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium"
require File.join(root, "method/lib/generation_cleanup")
require File.join(root, "method/lib/codex_usage")
raise "Generation incomplete" unless JSON.parse(File.read(File.join(root, "progress.json"))).fetch("status") == "complete"
raise "Test account not idle" unless GenerationCleanup.new.pids.empty?
validation = JSON.parse(File.read(File.join(root, "evaluation/revalidation-completion-review.json")))
raise "Affected validation incomplete" unless validation.fetch("verification") == "passed"
pricing = File.join(root, "pricing")
reader_root = "/tmp/gpt62-request-reader-20261125-ooeWyw"
preparation = JSON.parse(File.read(File.join(reader_root, "preparation.json")))
raise "Untested reader" unless preparation.fetch("tests_passed")
preparation.fetch("prepared_sha256").each do |name, digest|
  raise "Reader preparation changed" unless Digest::SHA256.file(File.join(reader_root, name)).hexdigest == digest
end
source_usage = File.join(root, "codex-usage.jsonl")
raise "Original exact usage changed" unless Digest::SHA256.file(source_usage).hexdigest == "f4cc9ed8724a4295675049d1a523a411482370f73657963490b5c55159054df0"
records = CodexUsage.load_records(source_usage)
raise "Incomplete final accounting" unless records.size == 440
output_path = File.join(pricing, "codex-request-usage.jsonl")
report_path = File.join(pricing, "request-context-audit.json")
raise "Context audit already exists" if File.exist?(output_path) || File.exist?(report_path)
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Native performance workload active" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
begin
  helper = File.join(reader_root, "read-request-usage.rb")
  output, error, status = Open3.capture3("su", "-", "llmtest", "--shell=/bin/bash", "-c",
    Shellwords.join(["ruby", helper]), stdin_data: JSON.generate(records.values))
  raise "Scoped native context recovery failed: #{error}" unless status.success?
ensure
  host_lock.close
end
rows = output.lines.map { |line| JSON.parse(line) }
raise "Recovered scope differs" unless rows.map { |row| row.fetch("run_id") } == records.keys
rows.each do |row|
  original = records.fetch(row.fetch("run_id"))
  raise "Final-usage binding differs" unless row.fetch("session_sha256") == original.fetch("session_sha256") &&
    row.fetch("exact_final_record_sha256") == Digest::SHA256.hexdigest(JSON.generate(original)) && row.fetch("total_usage") == original.fetch("usage")
end
profiles = rows.group_by { |row| row.fetch("run_id").match(/_(gpt-6\.2-(?:astra|sol)-medium)_/)[1] }.transform_values do |selected|
  totals = CodexUsage::FIELDS.to_h { |field| [field, selected.sum { |row| row.fetch("total_usage").fetch(field) }] }
  requests = selected.flat_map { |row| row.fetch("requests") }
  tiers = %w[short long].to_h do |tier|
    matching = requests.select { |request| (request.fetch("usage").fetch("input_tokens") > 272000 ? "long" : "short") == tier }
    [tier, { "requests" => matching.size, "usage" => CodexUsage::FIELDS.to_h { |field| [field, matching.sum { |request| request.fetch("usage").fetch(field) }] } }]
  end
  raise "Tier totals differ" unless CodexUsage::FIELDS.all? { |field| tiers.values.sum { |tier| tier.fetch("usage").fetch(field) } == totals.fetch(field) }
  { "observations" => selected.size, "requests" => requests.size,
    "max_request_input_tokens" => selected.map { |row| row.fetch("max_request_input_tokens") }.max,
    "model_context_windows" => selected.flat_map { |row| row.fetch("model_context_windows") }.uniq.sort,
    "duplicate_native_records_ignored" => selected.sum { |row| row.fetch("duplicate_records_ignored") },
    "token_count_snapshots_verified" => selected.sum { |row| row.fetch("token_count_snapshots_verified") },
    "total_usage" => totals, "by_context_tier" => tiers }
end
raise "Profile coverage differs" unless profiles.keys.sort == %w[gpt-6.2-astra-medium gpt-6.2-sol-medium] && profiles.values.all? { |profile| profile.fetch("observations") == 220 }
FileUtils.mkdir_p(pricing)
report = {
  "schema_version" => 1, "checked_at" => Time.now.utc.iso8601,
  "generation_complete_before_session_inspection" => true, "no_measurements_active_during_inspection" => true,
  "observations" => rows.size, "profiles" => profiles, "context_threshold_input_tokens" => 272000,
  "method" => "Retained exact final records select 440 sessions; each native response and cumulative/token-count stream reconciled, duplicate response IDs checked, original session digest verified. No model calls or raw transcript export.",
  "final_usage_sha256" => Digest::SHA256.file(source_usage).hexdigest,
  "request_usage_sha256" => Digest::SHA256.hexdigest(output), "request_usage_bytes" => output.bytesize,
  "reader_preparation_sha256" => Digest::SHA256.file(File.join(reader_root, "preparation.json")).hexdigest,
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
  "pricing_tier_selected" => false, "website_unchanged" => true
}
%w[read-request-usage.rb test-request-usage.rb codex_usage.rb tests.log preparation.json].each do |name|
  destination = File.join(pricing, name)
  raise "Reader evidence exists" if File.exist?(destination)
  FileUtils.cp(File.join(reader_root, name), destination)
end
File.write(output_path, output)
File.write(report_path, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, pricing)
puts JSON.pretty_generate(report)
