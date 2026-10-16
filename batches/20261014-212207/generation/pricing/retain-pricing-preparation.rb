# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "time"
require "bigdecimal"

output = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/pricing"
raise "Pricing already retained" if File.exist?(output)
snapshot = File.join(__dir__, "sonnet55-openrouter-endpoints.json")
data = JSON.parse(File.read(snapshot)).fetch("data")
raise "Wrong model" unless data.fetch("id") == "anthropic/claude-sonnet-5.5"
live = data.fetch("endpoints").select { |row| row.fetch("status") == 0 }
selected = live.find { |row| row.fetch("tag") == "anthropic" }
raise "No live Anthropic endpoint" unless selected
keys = %w[prompt input_cache_read completion]
expected = %w[0.000002 0.0000001 0.00001].map { |value| BigDecimal(value) }
raise "Published rates changed" unless selected.fetch("pricing").values_at(*keys).map { |v| BigDecimal(v) } == expected
live.each do |row|
  rates = row.fetch("pricing")
  raise "Unexpected context tier" unless Array(rates["overrides"]).empty?
  raise "Unexpected service tier" unless row["service_tier"].nil?
  raise "Cheaper endpoint requires review" if keys.zip(expected).any? { |key, price| BigDecimal(rates.fetch(key)) < price }
end
groups = live.group_by { |row| row.fetch("pricing").values_at(*keys) }.map do |rates, rows|
  { "tags" => rows.map { |row| row.fetch("tag") }.sort,
    "rates" => rates.map { |value| (BigDecimal(value) * 1_000_000).to_f } }
end
receipt = {
  "recorded_at" => Time.now.utc.iso8601, "as_of" => "2026-10-15",
  "model" => data.fetch("id"),
  "source_url" => "https://openrouter.ai/api/v1/models/anthropic/claude-sonnet-5.5/endpoints",
  "response_sha256" => Digest::SHA256.file(snapshot).hexdigest,
  "official_confirmation_url" => "https://platform.claude.com/docs/en/models/sonnet-5-5/overview",
  "units" => "USD per million tokens; input/cache-read/output",
  "endpoint_rate_groups" => groups, "selected_tag" => "anthropic",
  "selection" => "Componentwise lowest live non-batch rates, tied with four other endpoints; no request-context price tiers.",
  "cache_creation_policy" => "Standard input rate, as for the other Claude profiles.",
  "comparison" => "Normalized API-price comparison using retained native token totals, not the subscription bill.",
  "historical_profiles_changed" => false,
  "release_integration" => "Pending validation, timing review/correction and benchmark completion."
}
FileUtils.mkdir_p(output)
FileUtils.cp(snapshot, File.join(output, "openrouter-endpoints.json"))
FileUtils.cp(__FILE__, output)
File.write(File.join(output, "pricing-reference.json"), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt)
