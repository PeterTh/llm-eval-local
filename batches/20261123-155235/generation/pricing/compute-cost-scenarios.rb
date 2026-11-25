# frozen_string_literal: true
require "json"
require "digest"
require "bigdecimal"
require "fileutils"
require "time"

root = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/pricing"
output = File.join(root, "cost-scenarios.json")
raise "Cost scenarios already retained" if File.exist?(output)
options_path = File.join(root, "pricing-options.json")
usage_path = File.join(root, "request-context-audit.json")
options = JSON.parse(File.read(options_path))
usage = JSON.parse(File.read(usage_path))
raise "Request evidence changed" unless Digest::SHA256.file(File.join(root, "codex-request-usage.jsonl")).hexdigest == usage.fetch("request_usage_sha256")
raise "Context threshold differs" unless usage.fetch("context_threshold_input_tokens") == options.fetch("context_threshold_input_tokens")
costs = usage.fetch("profiles").to_h do |profile, observed|
  rates = options.fetch("standard_rates_usd_per_million").fetch(profile).transform_values { |rate| BigDecimal(rate.to_s) / 1_000_000 }
  standard = observed.fetch("by_context_tier").sum(BigDecimal("0")) do |tier, details|
    tokens = details.fetch("usage")
    raise "Cache-write mode requires explicit treatment" unless tokens.fetch("cache_write_input_tokens").zero?
    input_multiplier, output_multiplier = tier == "long" ? [2, BigDecimal("1.5")] : [1, 1]
    ((tokens.fetch("input_tokens") - tokens.fetch("cached_input_tokens")) * rates.fetch("input") +
      tokens.fetch("cached_input_tokens") * rates.fetch("cached_input")) * input_multiplier +
      tokens.fetch("output_tokens") * rates.fetch("output") * output_multiplier
  end
  [profile, options.fetch("non_batch_options").to_h do |name, multiplier|
    total = standard * BigDecimal(multiplier.to_s)
    [name, { "total_usd" => total.to_s("F"), "mean_usd_per_observation" => (total / observed.fetch("observations")).to_s("F") }]
  end]
end
report = {
  "created_at" => Time.now.utc.iso8601, "pricing_as_of" => options.fetch("pricing_as_of"),
  "status" => "Alternative API-equivalent cost scenarios only; no tier selected, no subscription bill inferred, no historical prices changed",
  "costs" => costs,
  "formula" => "(input - cached) * input_rate + cached * cache_rate + output * output_rate; request context multipliers applied before optional background discount. Reasoning is already included in output.",
  "input_sha256" => [options_path, usage_path].to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
  "script_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
File.write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, root)
puts JSON.pretty_generate(report.slice("status", "costs"))
