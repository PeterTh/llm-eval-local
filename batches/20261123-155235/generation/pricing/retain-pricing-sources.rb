# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "time"

source = "/tmp/gpt62-pricing-sources-20261125-fRT4jm"
root = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/pricing"
output = File.join(root, "pricing-options.json")
raise "Pricing references already retained" if File.exist?(output)
urls = {
  "astra-model.md" => "https://developers.openai.com/api/docs/models/gpt-6.2-astra.md",
  "sol-model.md" => "https://developers.openai.com/api/docs/models/gpt-6.2-sol.md",
  "pricing.md" => "https://developers.openai.com/api/docs/pricing.md",
  "background.md" => "https://developers.openai.com/api/docs/guides/background.md"
}
rates = {
  "gpt-6.2-astra-medium" => { "input" => 8, "cached_input" => 0.4, "output" => 40, "cache_write_30m" => 10, "cache_write_12h" => 20 },
  "gpt-6.2-sol-medium" => { "input" => 2, "cached_input" => 0.1, "output" => 10, "cache_write_30m" => 2.5, "cache_write_12h" => 5 }
}
%w[astra sol].each do |model|
  bytes = File.read(File.join(source, "#{model}-model.md"))
  raise "Wrong official model page" unless bytes.include?("Model ID: `gpt-6.2-#{model}`")
  expected = rates.fetch("gpt-6.2-#{model}-medium")
  { "Input" => "input", "Cached input" => "cached_input", "Output" => "output", "Cache writes" => "cache_write_30m" }.each do |metric, field|
    value = bytes.match(/^\| #{Regexp.escape(metric)} \| \$([0-9.]+) \| 1M tokens \|$/)&.captures&.first
    raise "Official rate differs: #{model}/#{field}" unless value && Float(value) == expected.fetch(field)
  end
  raise "Context policy differs" unless bytes.include?("more than 272K input tokens") && bytes.include?("input and cache rates double and output costs 1.5 times")
end
background = File.read(File.join(source, "background.md"))
raise "Missing replacement pricing policy" unless background.include?("new models launch without Flex processing") &&
  background.include?("30% below Standard") && background.include?("40% below Standard") &&
  background.include?("eligible request, including follow-ups")
FileUtils.mkdir_p(root)
sources = urls.to_h do |name, url|
  path = File.join(source, name)
  destination = File.join(root, name)
  raise "Pricing source exists" if File.exist?(destination)
  FileUtils.cp(path, destination)
  [name, { "url" => url, "sha256" => Digest::SHA256.file(path).hexdigest, "bytes" => File.size(path) }]
end
report = {
  "schema_version" => 1, "retrieved_at" => Time.now.utc.iso8601, "pricing_as_of" => "2026-11-25",
  "status" => "Options retained; final API-equivalent pricing tier not selected and no website/artifact edits made",
  "standard_rates_usd_per_million" => rates,
  "context_threshold_input_tokens" => 272000,
  "long_context_rule" => "For requests with input_tokens > 272000, multiply full-request input/cache rates by 2 and output by 1.5",
  "flex_available_for_these_models" => false,
  "non_batch_options" => { "standard" => 1.0, "background_2h" => 0.7, "background_8h" => 0.6 },
  "background_conditions" => "Responses API public beta, background=true, non-streaming and Standard processing; eligible follow-up tool requests also receive the discount. Queue scheduling differs from the measured Codex subscription harness.",
  "pending_release_discussion" => "Whether the existing cheapest non-batch API-equivalent comparison should select the new 8h background option, analogous to previously eligible Flex, or Standard. No historical profile is repriced.",
  "sources" => sources, "script_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
File.write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, root)
puts JSON.pretty_generate(report.slice("retrieved_at", "status", "standard_rates_usd_per_million", "non_batch_options"))
