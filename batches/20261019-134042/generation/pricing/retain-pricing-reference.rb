# frozen_string_literal: true
require "net/http"
require "json"
require "digest"
require "fileutils"
require "time"

campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
output = File.join(campaign, "pricing")
target = File.join(output, "pricing-reference.json")
raise "Pricing already retained" if File.exist?(target)
context_path = File.join(output, "request-context-summary.json")
context = JSON.parse(File.read(context_path))
complete = context.fetch("records").select { |row| row.fetch("usage_complete") }
raise "Complete usage scope changed" unless complete.size == 217
means = %w[input_tokens cached_input_tokens output_tokens].to_h do |key|
  [key, complete.sum { |row| row.fetch("token_counts").fetch(key) }.fdiv(complete.size)]
end
endpoint = "https://openrouter.ai/api/v1/models/deepseek/deepseek-v4.1-flash/endpoints"
response = Net::HTTP.get_response(URI(endpoint))
raise "Public pricing request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
data = JSON.parse(response.body).fetch("data")
raise "Wrong pricing model" unless data.fetch("id") == "deepseek/deepseek-v4.1-flash"
cost = lambda do |rates|
  ((means.fetch("input_tokens") - means.fetch("cached_input_tokens")) * rates.fetch("input") +
    means.fetch("cached_input_tokens") * rates.fetch("cached_input") + means.fetch("output_tokens") * rates.fetch("output")) / 1_000_000
end
candidates = data.fetch("endpoints").map do |row|
  pricing = row.fetch("pricing")
  rates = { "input" => Float(pricing.fetch("prompt")) * 1_000_000,
    "cached_input" => Float(pricing.fetch("input_cache_read", pricing.fetch("prompt"))) * 1_000_000,
    "output" => Float(pricing.fetch("completion")) * 1_000_000 }
  raise "Invalid endpoint rates" unless rates.values.all? { |value| value.finite? && value >= 0 }
  row.slice("name", "provider_name", "tag", "status", "quantization", "context_length", "max_completion_tokens", "pricing").merge(
    "rates_per_million" => rates, "estimated_mean_cost_usd" => cost.call(rates),
    "eligible" => row.fetch("status") == 0 && !row.fetch("tag").include?("batch"))
end
ranked = candidates.select { |row| row.fetch("eligible") }.sort_by { |row| [row.fetch("estimated_mean_cost_usd"), row.fetch("tag")] }
raise "No live pricing candidate" if ranked.empty?
report = {
  "schema_version" => 1, "checked_at" => Time.now.utc.iso8601, "model" => "deepseek-v4.1-flash",
  "profile" => "deepseek-v4.1-flash-oc-high", "currency" => "USD", "unit" => "per_million_tokens",
  "source_urls" => [endpoint, "https://api-docs.deepseek.com/quick_start/pricing/", "https://opencode.ai/v2/docs/console/go/"],
  "source_kind" => "Live public OpenRouter endpoint response; official DeepSeek and OpenCode Go pricing documentation checked on the recorded date",
  "endpoint_response_sha256" => Digest::SHA256.hexdigest(response.body),
  "native_context_sha256" => Digest::SHA256.file(context_path).hexdigest,
  "complete_cost_observations" => complete.size, "incomplete_cost_observations" => 3,
  "complete_observation_mean_tokens" => means,
  "selection_policy" => "Lowest estimated cost among live non-batch OpenRouter endpoints for the observed complete token mix; cached tokens use the input rate when no cache-read rate is listed. Historical profiles remain unchanged.",
  "selected" => ranked.first, "candidates" => candidates,
  "official_deepseek_off_peak" => { "input" => 0.15, "cached_input" => 0.003, "output" => 0.60 },
  "official_deepseek_peak" => { "input" => 0.30, "cached_input" => 0.006, "output" => 1.20 },
  "go_plus_monthly_fee_usd" => 40, "go_plus_deepseek_monthly_allowance_usd" => 160,
  "peak_hours" => "Monday-Friday 01:00-04:00 and 06:00-10:00 UTC, excluding Chinese public holidays",
  "interpretation" => "API-rate comparison, not the Go subscription bill or quota consumption. The selected endpoint is a different serving configuration; its declared model slug and quantization are retained. The evaluated Go alias is not an immutable weight snapshot. Three terminated observations retain exact completed-request lower bounds and are excluded from full-task cost statistics, not from scores or execution results.",
  "checker_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
File.write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, output)
puts JSON.pretty_generate(report.except("candidates"))
