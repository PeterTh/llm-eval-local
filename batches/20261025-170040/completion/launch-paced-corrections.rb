# frozen_string_literal: true
require "json"
require "yaml"
require "open3"
require "fileutils"
require "digest"
require "time"

scope = ARGV.fetch(0)
raise "Expected trial or full" unless ARGV.size == 1 && %w[trial full].include?(scope)
stage = scope == "trial" ? "pilot" : "full"
campaign = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation"
proposals = "/home/petert/llm_timing_fixes/20261028-haiku55-opencode-proposals"
unit = "llm-haiku55-oc-correction-#{stage}-20261028.service"
receipt_path = File.join(campaign, "correction-#{stage}-paced-launch.json")
raise "Paced stage already launched" if File.exist?(receipt_path)
gate_path = File.join(campaign, scope == "trial" ? "audit-completion-review.json" : "correction-pilot-gate.json")
gate = JSON.parse(File.read(gate_path))
raise "Gate failed" unless gate.fetch("passed") && (gate["unresolved"] || gate["unresolved_ids"]).empty?
gate.fetch("input_sha256").each { |path, digest| raise "Gate input changed" unless Digest::SHA256.file(path).hexdigest == digest }
%w[pilot full].each do |name|
  state, status = Open3.capture2("systemctl", "--user", "show", "llm-haiku55-oc-correction-#{name}-20261028.service", "-p", "ActiveState", "--value")
  raise "Cannot inspect correction service" unless status.success?
  raise "Correction service active" if %w[active activating deactivating].include?(state.strip)
end
cli = JSON.parse(File.read(File.join(campaign, "audit-pilot-launch.json")))
raise "Reviewer CLI changed" unless File.realpath("/home/petert/.local/bin/codex") == cli.fetch("review_cli_path") && Digest::SHA256.file(cli.fetch("review_cli_path")).hexdigest == cli.fetch("review_cli_sha256")
original_driver = File.join(__dir__, "correction-#{stage}-driver.rb")
raise "Original driver changed" unless File.binread(original_driver) == File.binread(File.join(campaign, File.basename(original_driver)))
ids = scope == "trial" ? File.readlines(File.join(proposals, "trial-ids.txt"), chomp: true).reject(&:empty?) : File.readlines(File.join(proposals, "inventory.jsonl")).map { |line| JSON.parse(line).fetch("id") }
retained = Dir[File.join(proposals, "proposals/*.json")].sort.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
raise "Unexpected proposal coverage" unless ids.size == (scope == "trial" ? 16 : 36) && retained.size == (scope == "trial" ? 12 : 16)
last_429 = Dir[File.join(proposals, "logs/*/attempt-*/metadata.yaml")].filter_map do |path|
  metadata = YAML.safe_load_file(path)
  Time.parse(metadata.fetch("finished_at")) if metadata.fetch("transport_errors", []).any? { |error| error.include?("429 Too Many Requests") }
end.max
driver = File.join(__dir__, "paced-correction-driver.rb")
log = File.join(campaign, "correction-#{stage}-paced-driver.log")
raise "Paced log already exists" if File.exist?(log)
canonical_receipt = File.join(campaign, "correction-full-launch.json")
raise "Full stage already launched" if scope == "full" && File.exist?(canonical_receipt)
report = {
  "prepared_at" => Time.now.utc.iso8601, "unit" => unit, "scope" => scope,
  "driver_sha256" => Digest::SHA256.file(driver).hexdigest,
  "original_driver_sha256" => Digest::SHA256.file(original_driver).hexdigest,
  "gate_path" => gate_path, "gate_sha256" => Digest::SHA256.file(gate_path).hexdigest,
  "selected_ids" => ids, "retained_proposals" => retained,
  "not_before" => [Time.now, (last_429 || Time.at(0)) + 600].max.utc.iso8601,
  "minimum_request_spacing_seconds" => 90, "rate_limit_backoff_seconds" => [600, 1200],
  "maximum_consecutive_429_failures_per_program" => 3,
  "proposal_workers" => 1, "proposal_model" => "gpt-6.1-sol", "proposal_effort" => "high",
  "model_workers_source_only" => true, "scientific_policy_changed" => false,
  "policy" => "Operational pacing only. Reuse exact accepted proposals; stop on non-429 errors or three consecutive 429 failures; then continue the immutable compilation and independent-review driver."
}
File.write(receipt_path, JSON.pretty_generate(report) + "\n", mode: "wx")
[__FILE__, driver].each { |path| FileUtils.cp(path, campaign) }
raise "Paced launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Haiku timing corrections with bounded rate-limit pacing",
  "--property=WorkingDirectory=#{__dir__}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", "/usr/bin/ruby", "-rtime", driver, scope)
current, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "InvocationID")
raise "Cannot inspect paced service" unless status.success?
properties = current.lines.to_h { |line| line.chomp.split("=", 2) }
raise "Paced service did not start" unless properties.fetch("ActiveState") == "active"
# The receipt consumed by the driver stays immutable; activation is separate.
activation = { "launched_at" => Time.now.utc.iso8601, "unit" => unit,
  "properties" => properties, "driver_sha256" => report.fetch("driver_sha256"),
  "pacing_receipt_sha256" => Digest::SHA256.file(receipt_path).hexdigest,
  "corrections" => 36, "reused_pilot_corrections" => scope == "full" ? 16 : nil }
File.write(File.join(campaign, "correction-#{stage}-paced-activation.json"), JSON.pretty_generate(activation) + "\n", mode: "wx")
File.write(canonical_receipt, JSON.pretty_generate(activation) + "\n", mode: "wx") if scope == "full"
puts JSON.pretty_generate(activation.merge(report.slice("not_before", "minimum_request_spacing_seconds", "rate_limit_backoff_seconds")))
