# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "shellwords"
require "bigdecimal"
require "time"

root = "/home/petert/llm_para_campaigns/20261028-200951-terra61-codex-medium"
require File.join(root, "method/lib/generation_cleanup")
require File.join(root, "method/lib/codex_usage")
raise "Generation incomplete" unless JSON.parse(File.read(File.join(root, "progress.json"))).fetch("status") == "complete"
raise "Test account not idle" unless GenerationCleanup.new.pids.empty?
pricing = File.join(root, "pricing")
reference_path = File.join(pricing, "pricing-reference.json")
reference = JSON.parse(File.read(reference_path))
raise "Unexpected pricing policy" unless reference.fetch("profile") == "gpt-6.1-terra-medium" &&
  reference.fetch("selected").fetch("tag") == "openai/flex" && reference.fetch("context_threshold_input_tokens") == 272000
source_usage = File.join(root, "codex-usage.jsonl")
records = CodexUsage.load_records(source_usage)
raise "Incomplete final accounting" unless records.size == 220
output_path = File.join(pricing, "codex-request-usage.jsonl")
report_path = File.join(pricing, "request-pricing-audit.json")
raise "Pricing audit already exists" if File.exist?(output_path) || File.exist?(report_path)
test_output, test_error, test_status = Open3.capture3("ruby", File.join(__dir__, "test-request-usage.rb"), "--seed", "20261029")
raise "Counter-reader regression failed: #{test_error}" unless test_status.success? && test_output.include?("6 runs, 9 assertions, 0 failures, 0 errors, 0 skips")
helper = File.join(__dir__, "read-request-usage.rb")
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Native performance workload active" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
begin
  output, error, status = Open3.capture3("su", "-", "llmtest", "--shell=/bin/bash", "-c",
    Shellwords.join(["ruby", helper]), stdin_data: JSON.generate(records.values))
  raise "Scoped native counter recovery failed: #{error}" unless status.success?
ensure
  host_lock.close
end
rows = output.lines.map { |line| JSON.parse(line) }
raise "Recovered scope differs" unless rows.map { |row| row.fetch("run_id") } == records.keys
rows.each do |row|
  original = records.fetch(row.fetch("run_id"))
  raise "Final-usage binding differs" unless row.fetch("session_sha256") == original.fetch("session_sha256") &&
    row.fetch("exact_final_record_sha256") == Digest::SHA256.hexdigest(JSON.generate(original)) &&
    row.fetch("total_usage") == original.fetch("usage")
end
threshold = reference.fetch("context_threshold_input_tokens")
rate = ->(value) { BigDecimal(value.to_s) / 1_000_000 }
short_rates = reference.fetch("short_rates_usd_per_million").transform_values { |value| rate.call(value) }
long_rates = reference.fetch("long_rates_usd_per_million").transform_values { |value| rate.call(value) }
totals = CodexUsage::FIELDS.to_h { |field| [field, 0] }
bands = %w[short long].to_h { |band| [band, { "requests" => 0, "input_tokens" => 0, "cached_input_tokens" => 0, "output_tokens" => 0 }] }
total_cost = BigDecimal("0")
run_costs = rows.map do |row|
  cost = BigDecimal("0")
  row.fetch("requests").each do |request|
    usage = request.fetch("usage")
    raise "Unexpected cache-write usage requires explicit pricing" unless usage.fetch("cache_write_input_tokens").zero?
    band = usage.fetch("input_tokens") > threshold ? "long" : "short"
    selected_rates = band == "long" ? long_rates : short_rates
    bands.fetch(band)["requests"] += 1
    %w[input_tokens cached_input_tokens output_tokens].each { |field| bands.fetch(band)[field] += usage.fetch(field) }
    totals.each_key { |field| totals[field] += usage.fetch(field) }
    cost += (usage.fetch("input_tokens") - usage.fetch("cached_input_tokens")) * selected_rates.fetch("prompt") +
      usage.fetch("cached_input_tokens") * selected_rates.fetch("input_cache_read") +
      usage.fetch("output_tokens") * selected_rates.fetch("completion")
  end
  total_cost += cost
  { "run_id" => row.fetch("run_id"), "requests" => row.fetch("request_count"),
    "max_request_input_tokens" => row.fetch("max_request_input_tokens"), "api_equivalent_cost_usd" => cost.to_s("F") }
end
expected = totals.keys.to_h { |field| [field, records.values.sum { |record| record.fetch("usage").fetch(field) }] }
raise "Cross-observation token sums differ" unless totals == expected
report = {
  "schema_version" => 1, "checked_at" => Time.now.utc.iso8601, "profile" => reference.fetch("profile"),
  "source" => "Exact per-response native usage, deduplicated by response ID and checked against every native cumulative record, token-count stream and final retained usage record",
  "generation_complete_before_session_inspection" => true, "observations" => rows.size,
  "requests" => rows.sum { |row| row.fetch("request_count") },
  "duplicate_native_records_ignored" => rows.sum { |row| row.fetch("duplicate_records_ignored") },
  "token_count_snapshots_verified" => rows.sum { |row| row.fetch("token_count_snapshots_verified") },
  "max_request_input_tokens" => rows.map { |row| row.fetch("max_request_input_tokens") }.max,
  "context_threshold_input_tokens" => threshold, "long_context_rule" => "input_tokens > 272000; full-request rates",
  "by_context_tier" => bands, "total_usage" => totals,
  "cache_write_input_tokens_known_zero" => true,
  "pricing_as_of" => reference.fetch("pricing_as_of"), "selected_endpoint" => reference.fetch("selected").slice("name", "tag", "service_tier"),
  "total_api_equivalent_cost_usd" => total_cost.to_s("F"),
  "mean_api_equivalent_cost_usd" => (total_cost / rows.size).to_s("F"),
  "pricing_reference_sha256" => Digest::SHA256.file(reference_path).hexdigest,
  "final_usage_sha256" => Digest::SHA256.file(source_usage).hexdigest,
  "request_usage_sha256" => Digest::SHA256.hexdigest(output), "request_usage_bytes" => output.bytesize,
  "reader_sha256" => Digest::SHA256.file(helper).hexdigest,
  "codex_usage_library_sha256" => Digest::SHA256.file(File.join(root, "method/lib/codex_usage.rb")).hexdigest,
  "test_sha256" => Digest::SHA256.file(File.join(__dir__, "test-request-usage.rb")).hexdigest,
  "tests" => { "runs" => 6, "assertions" => 9, "failures" => 0, "errors" => 0, "seed" => 20261029 },
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
  "scope" => "Terra only; historical prices and measurements unchanged. API-rate comparison, not subscription billing.",
  "runs" => run_costs
}
%w[read-request-usage.rb test-request-usage.rb audit-pricing.rb].each { |name| FileUtils.cp(File.join(__dir__, name), File.join(pricing, name)) }
File.write(File.join(pricing, "request-usage-tests.log"), test_output + test_error)
File.write("#{output_path}.tmp", output)
File.rename("#{output_path}.tmp", output_path)
File.write("#{report_path}.tmp", JSON.pretty_generate(report) + "\n")
File.rename("#{report_path}.tmp", report_path)
puts JSON.pretty_generate(report.reject { |key, _| key == "runs" })
