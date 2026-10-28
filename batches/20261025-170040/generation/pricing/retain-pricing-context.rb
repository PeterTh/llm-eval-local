# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "net/http"
require "bigdecimal"
require "time"
require_relative "experiment/lib/opencode_generation_observation"

root = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium"
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
completion = JSON.parse(File.read(File.join(root, "completion.json")))
output = File.join(root, "pricing")
raise "Pricing already retained" if File.exist?(output)
batch = manifest.fetch("campaign_id")
source = manifest.fetch("persistent_results")
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true).sort
raise "Incomplete source scope" unless ids.size == 220 && completion.fetch("observations") == 220
endpoint = "https://openrouter.ai/api/v1/models/anthropic/claude-haiku-5.5/endpoints"
uri = URI(endpoint)
response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 30) { |http| http.get(uri.request_uri) }
raise "Public endpoint lookup failed" unless response.is_a?(Net::HTTPSuccess)
data = JSON.parse(response.body).fetch("data")
raise "Wrong pricing model" unless data.fetch("id") == "anthropic/claude-haiku-5.5"
candidates = data.fetch("endpoints").map do |row|
  pricing = row.fetch("pricing")
  tier = pricing.fetch("overrides").find { |r| r.fetch("min_prompt_tokens") == 100000 }
  raise "Missing Haiku context tier" unless tier
  rates = { "short" => pricing, "long" => tier }.transform_values do |p|
    { "input" => "prompt", "cached_input" => "input_cache_read", "output" => "completion" }.to_h do |key, name|
      n = BigDecimal(p.fetch(name)) * 1_000_000_000
      raise "Invalid comparison rate" unless n.finite? && n >= 0 && n.frac.zero?
      [key, n.to_i]
    end
  end
  row.slice("name", "provider_name", "tag", "status", "quantization", "context_length", "pricing").merge(
    "rates_nanodollars_per_token" => rates, "eligible" => row.fetch("status") == 0 && !row.fetch("tag").include?("batch"))
end
selected = candidates.find { |c| c.fetch("tag") == "anthropic" && c.fetch("eligible") }
raise "Anthropic public endpoint unavailable" unless selected
rates = selected.fetch("rates_nanodollars_per_token")
expected_rates = { "short" => { "input" => 100, "cached_input" => 10, "output" => 500 }, "long" => { "input" => 500, "cached_input" => 50, "output" => 2500 } }
raise "Haiku public rates changed" unless rates == expected_rates
raise "Lower live non-batch rate needs selection" unless candidates.select { |c| c.fetch("eligible") }.all? do |candidate|
  rates.all? { |band, values| values.all? { |key, value| candidate.fetch("rates_nanodollars_per_token").fetch(band).fetch(key) >= value } }
end
date = Time.now.utc.strftime("%Y-%m-%d")
records = ids.map do |id|
  observation = JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  raise "Incomplete usage: #{id}" unless observation.fetch("usage_complete")
  session_path = File.join(source, id, "opencode-session.txt")
  sha = Digest::SHA256.file(session_path).hexdigest
  raise "Session changed: #{id}" unless sha == observation.fetch("sha256").fetch("opencode-session.txt")
  session = JSON.parse(File.read(session_path))
  steps = session.fetch("messages").flat_map { |message| message.fetch("parts").select { |part| part.fetch("type") == "step-finish" } }
  raise "Missing/duplicate native accounting" if steps.empty? || steps.map { |s| s.fetch("id") }.uniq.size != steps.size
  usages = steps.map { |step| OpenCodeGenerationObservation.normalize_usage(step.fetch("tokens")) }
  totals = usages.first.keys.to_h { |key| [key, usages.sum { |counts| counts.fetch(key) }] }
  raise "Native counters differ: #{id}" unless totals == observation.fetch("token_counts")
  bands = %w[short long].to_h do |name|
    [name, %w[requests input_tokens cache_read_input_tokens cache_write_input_tokens inclusive_input_tokens output_tokens reasoning_output_tokens max_request_input_tokens].to_h { |key| [key, 0] }]
  end
  usages.each do |usage|
    band = bands.fetch(usage.fetch("input_tokens") > 100000 ? "long" : "short")
    cached, written = usage.values_at("cached_input_tokens", "cache_write_input_tokens")
    ordinary = usage.fetch("input_tokens") - cached - written
    raise "Invalid disjoint input counters" if ordinary.negative?
    band["requests"] += 1
    band["input_tokens"] += ordinary
    band["cache_read_input_tokens"] += cached
    band["cache_write_input_tokens"] += written
    band["inclusive_input_tokens"] += usage.fetch("input_tokens")
    band["output_tokens"] += usage.fetch("output_tokens")
    band["reasoning_output_tokens"] += usage.fetch("reasoning_output_tokens")
    band["max_request_input_tokens"] = [band.fetch("max_request_input_tokens"), usage.fetch("input_tokens")].max
  end
  cost = bands.sum do |name, band|
    p = rates.fetch(name)
    (band.fetch("input_tokens") + band.fetch("cache_write_input_tokens")) * p.fetch("input") +
      band.fetch("cache_read_input_tokens") * p.fetch("cached_input") + band.fetch("output_tokens") * p.fetch("output")
  end
  {
    "schema_version" => 2, "id" => id, "batch" => batch, "profile" => id.split("_")[1],
    "source_commit" => completion.fetch("source_commit"), "session_id" => observation.fetch("session_id"),
    "native_session_sha256" => sha, "pricing_as_of" => date, "request_input_threshold_tokens" => 100000,
    "requests" => steps.size, "per_request_output_available" => true,
    "output_band_evidence" => "native_step_finish_per_request", "usage_complete" => true,
    "comparison_cost_nanodollars" => cost, "token_counts" => totals, "bands" => bands
  }
end
summary = {
  "schema_version" => 2, "checked_at" => Time.now.utc.iso8601, "source_batch" => batch,
  "source_commit" => completion.fetch("source_commit"), "programs" => records.size,
  "complete_programs" => records.size, "incomplete_programs" => 0,
  "requests" => records.sum { |r| r.fetch("requests") },
  "maximum_request_input_tokens" => records.flat_map { |r| r.fetch("bands").values.map { |b| b.fetch("max_request_input_tokens") } }.max,
  "requests_above_100000_tokens" => records.sum { |r| r.dig("bands", "long", "requests") },
  "observations_with_long_requests" => records.count { |r| r.dig("bands", "long", "requests") > 0 },
  "comparison_cost_nanodollars" => records.sum { |r| r.fetch("comparison_cost_nanodollars") },
  "pricing_context_policy" => "request_input_above_100000", "usage_complete" => true,
  "method" => "Exact native completed-request step-finish counters, including compaction; input includes cache read/write and output includes reasoning. Session hashes and cumulative totals match every retained observation. Request input above 100000 selects the higher tier for all input and output of that request. Cache creation uses ordinary input rates for comparison, matching prior Claude profiles. No output split inferred from list-price totals; no subscription bill inferred.",
  "checker_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
reference = {
  "schema_version" => 1, "checked_at" => summary.fetch("checked_at"), "pricing_as_of" => date,
  "profile" => "claude-haiku-5.5-oc-medium", "pricing_model_id" => "anthropic/claude-haiku-5.5",
  "source_urls" => [endpoint, "https://platform.claude.com/docs/en/models/haiku-5-5/overview", "https://platform.claude.com/docs/en/about-claude/pricing#long-context-pricing", "https://opencode.ai/v2/docs/console/go/"],
  "selection_policy" => "Anthropic tied for componentwise lowest live non-batch public rates in both request-context bands. Historical model profiles unchanged.",
  "selected" => selected, "candidates" => candidates, "endpoint_response_sha256" => Digest::SHA256.hexdigest(response.body),
  "threshold_definition" => "Strictly greater than 100000 inclusive input tokens, per official Anthropic documentation; 100000 itself uses the short tier.",
  "comparison_policy" => "Exact request-level counters; cache creation priced as ordinary input. API-rate estimate, not Go quota or actual subscription billing. No cache-lifetime assumption is needed.",
  "go_plus_subscription_usd_per_month" => 40, "go_plus_haiku_allowance_usd_per_month" => 60
}
FileUtils.mkdir_p(output)
usage_path = File.join(output, "context-usage.jsonl")
File.write(usage_path, records.map { |r| JSON.generate(r) + "\n" }.join)
summary["context_usage_sha256"] = Digest::SHA256.file(usage_path).hexdigest
reference["context_usage_sha256"] = summary.fetch("context_usage_sha256")
File.write(File.join(output, "request-context-summary.json"), JSON.pretty_generate(summary) + "\n")
File.write(File.join(output, "pricing-reference.json"), JSON.pretty_generate(reference) + "\n")
FileUtils.cp(__FILE__, output)
puts JSON.pretty_generate(summary)
