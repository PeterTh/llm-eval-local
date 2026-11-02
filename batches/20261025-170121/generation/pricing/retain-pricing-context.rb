# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "bigdecimal"
require "time"
require_relative "experiment/lib/opencode_generation_observation"

root = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium"
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
completion = JSON.parse(File.read(File.join(root, "completion.json")))
output = File.join(root, "pricing")
raise "Pricing already retained" if File.exist?(output)
response_path = File.join(__dir__, "beam-public-pricing-response.json")
body = File.binread(response_path)
data = JSON.parse(body).fetch("data")
raise "Wrong pricing model" unless data.fetch("id") == "reflection/beam-1.0-501b-a23b"
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true).sort
raise "Incomplete source scope" unless ids.size == 220 && completion.fetch("observations") == 220
records = ids.map do |id|
  observation = JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  path = File.join(manifest.fetch("persistent_results"), id, "opencode-session.txt")
  sha = Digest::SHA256.file(path).hexdigest
  raise "Native session changed" unless sha == observation.fetch("sha256").fetch("opencode-session.txt")
  session = JSON.parse(File.read(path))
  steps = session.fetch("messages").flat_map { |message| message.fetch("parts") }.select { |part| part["type"] == "step-finish" }
  raise "Missing/duplicate request counters" if steps.empty? || steps.map { |part| part.fetch("id") }.uniq.size != steps.size
  usage = steps.map { |part| OpenCodeGenerationObservation.normalize_usage(part.fetch("tokens")) }
  totals = usage.first.keys.to_h { |key| [key, usage.sum { |counts| counts.fetch(key) }] }
  raise "Native accounting differs" unless totals == observation.fetch("token_counts")
  raise "Unexpected cache writes need pricing review" unless totals.fetch("cache_write_input_tokens").zero?
  { "schema_version" => 1, "id" => id, "batch" => manifest.fetch("campaign_id"),
    "profile" => "beam-1.0-oc-medium", "source_commit" => completion.fetch("source_commit"),
    "session_id" => observation.fetch("session_id"), "native_session_sha256" => sha,
    "usage_complete" => observation.fetch("usage_complete"), "generation_outcome" => observation.fetch("outcome"),
    "requests" => steps.size, "max_request_input_tokens" => usage.map { |counts| counts.fetch("input_tokens") }.max,
    "max_request_output_tokens" => usage.map { |counts| counts.fetch("output_tokens") }.max,
    "token_counts" => totals }
end
complete, partial = records.partition { |record| record.fetch("usage_complete") }
raise "Unexpected partial scope" unless complete.size == 219 && partial.map { |row| row.fetch("id") } == ["matmul_beam-1.0-oc-medium_mpi_r3"]
observed = complete.first.fetch("token_counts").keys.to_h { |key| [key, complete.sum { |row| row.fetch("token_counts").fetch(key) }] }
cost = lambda do |tokens, rates|
  (tokens.fetch("input_tokens") - tokens.fetch("cached_input_tokens")) * rates.fetch("input") +
    tokens.fetch("cached_input_tokens") * rates.fetch("cached_input") + tokens.fetch("output_tokens") * rates.fetch("output")
end
candidates = data.fetch("endpoints").map do |row|
  pricing = row.fetch("pricing")
  raise "Context-tier pricing requires per-request calculation" if pricing["overrides"] && !pricing.fetch("overrides").empty?
  rates = { "input" => "prompt", "cached_input" => "input_cache_read", "output" => "completion" }.to_h do |key, field|
    rate = BigDecimal(pricing.fetch(field) { pricing.fetch("prompt") }) * 1_000_000_000
    raise "Invalid comparison rate" unless rate.finite? && rate >= 0 && rate.frac.zero?
    [key, rate.to_i]
  end
  eligible = row.fetch("status") == 0 && !row.fetch("tag").include?("batch") &&
    row.fetch("context_length") >= records.map { |record| record.fetch("max_request_input_tokens") }.max
  row.slice("name", "provider_name", "tag", "status", "quantization", "context_length", "pricing").merge(
    "rates_nanodollars_per_token" => rates, "eligible" => eligible,
    "complete_observation_cost_nanodollars" => cost.call(observed, rates))
end
selected = candidates.select { |candidate| candidate.fetch("eligible") }.min_by do |candidate|
  [candidate.fetch("complete_observation_cost_nanodollars"), candidate.fetch("tag")]
end
raise "No eligible public non-batch endpoint" unless selected
rates = selected.fetch("rates_nanodollars_per_token")
records.each do |record|
  record["comparison_cost_nanodollars"] = record.fetch("usage_complete") ? cost.call(record.fetch("token_counts"), rates) : nil
end
total = complete.sum { |record| record.fetch("comparison_cost_nanodollars") }
summary = {
  "schema_version" => 1, "checked_at" => Time.now.utc.iso8601, "source_batch" => manifest.fetch("campaign_id"),
  "source_commit" => completion.fetch("source_commit"), "programs" => records.size,
  "complete_programs" => complete.size, "incomplete_programs" => partial.size,
  "requests_with_exact_counters" => records.sum { |record| record.fetch("requests") },
  "maximum_request_input_tokens" => records.map { |record| record.fetch("max_request_input_tokens") }.max,
  "maximum_request_output_tokens" => records.map { |record| record.fetch("max_request_output_tokens") }.max,
  "complete_observation_token_counts" => observed,
  "partial_usage" => partial.map { |record| record.slice("id", "requests", "token_counts") },
  "comparison_cost_nanodollars" => total, "mean_complete_task_cost_usd" => total.fdiv(complete.size * 1_000_000_000),
  "pricing_context_policy" => "flat_published_rates",
  "method" => "Exact native per-request counters including compaction; inclusive input contains cache and inclusive output contains reasoning. One terminated session retains completed-request lower bounds only and is excluded from complete-task costs, not from validation or scores. Cache writes are zero. API-rate comparison is distinct from the temporary free Go route and subscription billing.",
  "checker_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
reference = {
  "schema_version" => 1, "checked_at" => summary.fetch("checked_at"), "pricing_as_of" => File.mtime(response_path).utc.strftime("%Y-%m-%d"),
  "profile" => "beam-1.0-oc-medium", "pricing_model_id" => data.fetch("id"),
  "source_urls" => ["https://openrouter.ai/api/v1/models/reflection/beam-1.0-501b-a23b/endpoints", "https://openrouter.ai/reflection/beam-1.0-501b-a23b", "https://reflection.ai/beam-model-card", "https://opencode.ai/v2/docs/console/go/"],
  "selection_policy" => "Cheapest live non-batch OpenRouter endpoint for the complete observed token mix, with listed cache-read rate or ordinary input rate when absent; frozen historical profiles unchanged.",
  "selected" => selected, "candidates" => candidates, "endpoint_response_sha256" => Digest::SHA256.hexdigest(body),
  "comparison_policy" => "API-rate estimate, not actual Go usage or subscription billing. The evaluated unversioned Go alias and paid comparison endpoint need not have identical serving configurations.",
  "go_promotion" => { "route" => "opencode-go/beam-free", "input_usd_per_million" => 0, "cached_input_usd_per_million" => 0,
    "output_usd_per_million" => 0, "temporary_free_offer" => true, "paid_fallback_used" => false,
    "source_url" => "https://opencode.ai/v2/docs/console/go/", "checked_on" => "2026-10-30" }
}
FileUtils.mkdir_p(output)
usage = records.map { |record| JSON.generate(record) + "\n" }.join
File.write(File.join(output, "request-usage.jsonl"), usage, mode: "wx")
summary["request_usage_sha256"] = Digest::SHA256.hexdigest(usage)
reference["request_usage_sha256"] = summary.fetch("request_usage_sha256")
File.write(File.join(output, "request-context-summary.json"), JSON.pretty_generate(summary) + "\n", mode: "wx")
File.write(File.join(output, "pricing-reference.json"), JSON.pretty_generate(reference) + "\n", mode: "wx")
FileUtils.cp(__FILE__, output)
puts JSON.pretty_generate(summary.merge("selected_provider" => selected.fetch("tag"), "rates_nanodollars_per_token" => rates))
