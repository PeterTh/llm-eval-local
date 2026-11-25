# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "time"

campaign = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium"
pricing = File.join(campaign, "pricing")
options_path = File.join(pricing, "pricing-options.json")
scenarios_path = File.join(pricing, "cost-scenarios.json")
options = JSON.parse(File.read(options_path))
scenarios = JSON.parse(File.read(scenarios_path))
reference = File.join(pricing, "pricing-reference.json")
raise "Pricing selection already recorded" if File.exist?(reference)
report = {
  "schema_version" => 1, "recorded_at" => Time.now.utc.iso8601,
  "pricing_as_of" => "2026-11-25", "status" => "selected_by_user",
  "user_decision" => "Use Standard pricing",
  "question_item_id" => '["request_user_input_async","call_b40e5453a7d24e99a6044145051c0048",1]',
  "selected" => { "provider" => "OpenAI", "service_tier" => "default", "pricing_tier" => "standard", "background_discount" => false },
  "profiles" => options.fetch("standard_rates_usd_per_million").to_h do |profile, rates|
    long = rates.dup
    rates.each { |key, value| long[key] = value * (key == "output" ? 1.5 : 2) }
    [profile, { "short_rates_usd_per_million" => rates, "long_rates_usd_per_million" => long,
                "cost_summary" => scenarios.fetch("costs").fetch(profile).fetch("standard") }]
  end,
  "context_threshold_input_tokens" => options.fetch("context_threshold_input_tokens"),
  "long_context_rule" => options.fetch("long_context_rule"),
  "sources" => options.fetch("sources"),
  "input_sha256" => [options_path, scenarios_path, File.join(pricing, "request-context-audit.json")].to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
  "scope" => "Only new Astra/Sol 6.2 API-equivalent costs. Historical prices, measured generation times and subscription accounting unchanged. Website not edited.",
  "script_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
File.write(reference, JSON.pretty_generate(report) + "\n")

site = "/home/petert/llm-eval-local/web/config/site.json"
config = JSON.parse(File.read(site))
old_excluded = config.fetch("modelSets").find { |set| set.fetch("id") == "default" }.fetch("excludeModelIds")
ids = (config.fetch("labels").fetch("models").keys + %w[gpt-6.2-astra-medium gpt-6.2-sol-medium]).sort
additional = %w[gpt-6-astra-medium gpt-6-sol-medium gpt-6.1-sol-medium gpt-6.1-sol-xhigh gpt-6.1-sol-oc-medium claude-fable-5-cc-medium claude-opus-5-cc-medium claude-sonnet-5-cc-medium deepseek-v4-flash].sort
raise "Unexpected baseline model count" unless ids.size == 43 && ids.uniq == ids && (ids - old_excluded).size == 36
raise "Invalid additional exclusion" unless (additional - ids).empty? && (additional & old_excluded).empty?
proposal = {
  "created_at" => Time.now.utc.iso8601, "status" => "exact_exclusions_proposed_not_applied",
  "user_principle" => "Retain distinct generations such as Sol5.6, but only the latest closely related6.0/6.1/6.2version; similarly for comparable families.",
  "existing_exclusions" => old_excluded, "additional_exclusions" => additional,
  "proposed_visible_ids" => ids - (old_excluded + additional),
  "proposed_visible_count" => 27, "all_profile_count" => 43,
  "point_to_confirm" => "Literal version pruning also hides Sol6.1 XHigh/OpenCode. Keeping the whole Sol6.1 comparison set instead would leave30 visible profiles.",
  "source_config_sha256" => Digest::SHA256.file(site).hexdigest,
  "website_unchanged" => true, "all_results_retained" => true
}
destination = File.join(campaign, "evaluation/default-visible-set-proposal.json")
raise "Visibility proposal already exists" if File.exist?(destination)
File.write(destination, JSON.pretty_generate(proposal) + "\n")
FileUtils.cp(__FILE__, File.join(campaign, "evaluation"))
puts JSON.pretty_generate({ "pricing" => report.slice("status", "user_decision", "profiles"), "visibility" => proposal })
