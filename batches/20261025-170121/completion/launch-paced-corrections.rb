# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"
require_relative "verified-external-validation"
stage, mode = ARGV
raise "Use pilot|full check|launch" unless ARGV.size == 2 && %w[pilot full].include?(stage) && %w[check launch].include?(mode)
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
external = BeamExternalValidation.verify!
proposals = "/home/petert/llm_timing_fixes/20261030-beam10-opencode-proposals"
audit_path = File.join(campaign, "audit-completion-supplemental-review.json")
audit = JSON.parse(File.read(audit_path))
raise "Unresolved audit" unless audit.fetch("passed") && audit.fetch("unresolved").empty? && audit.fetch("unique_programs") == 88
raise "Timing audit count changed" unless audit.fetch("verdicts").fetch("invalid") == 57
corrections = 57 - external.fetch(:excluded).size
gate_path = File.join(campaign, stage == "pilot" ? "audit-completion-supplemental-review.json" : "correction-pilot-gate.json")
gate = JSON.parse(File.read(gate_path))
raise "Correction gate failed" unless gate.fetch("passed") && (gate["unresolved"] || gate.fetch("unresolved_ids")).empty?
gate.fetch("input_sha256").each { |path, sha| raise "Gate input changed: #{path}" unless Digest::SHA256.file(path).hexdigest == sha }
fable = JSON.parse(File.read("/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/progress.json"))
raise "Fable not paused" unless fable.values_at("status", "completed", "active_id") == ["quota_paused", 194, nil]
raise "Fable STOP missing" unless File.file?("/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/STOP")
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
units = %w[llm-fable51-generation-20261011-092100.service llm-beam10-oc-timing-full-resume-20261031.service llm-beam10-oc-timing-supplemental-20261031.service llm-beam10-oc-timing-communication-20261031.service llm-beam10-oc-correction-pilot-20261031.service llm-beam10-oc-correction-full-20261031.service]
units.each do |unit|
  state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
  raise "Competing activity: #{unit}" unless status.success? && state.strip == "inactive"
end
cli = JSON.parse(File.read(File.join(campaign, "audit-pilot-launch.json")))
cli_path = cli.fetch("review_cli_path")
raise "Reviewer CLI changed" unless Digest::SHA256.file(cli_path).hexdigest == cli.fetch("review_cli_sha256")
retained = Dir["/home/petert/llm_timing_fixes/20261030-beam10-opencode-{proposals,review-pilot,review-pilot-sol61}/{proposals,results}/*.json"].sort.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
if stage == "pilot"
  raise "Unexpected pre-existing correction inventory" if File.exist?(proposals)
  raise "Unexpected retained corrections" unless retained.empty?
else
  raise "Wrong pilot size" unless gate.fetch("records") == 16
  raise "Wrong correction inventory" unless File.readlines(File.join(proposals, "inventory.jsonl")).size == corrections
  raise "Wrong accepted pilot proposal count" unless Dir[File.join(proposals, "proposals/*.json")].size == 16
end
unit = "llm-beam10-oc-correction-#{stage}-20261031.service"
receipt_path = File.join(campaign, "correction-#{stage}-launch.json")
log = File.join(campaign, "correction-#{stage}-paced-driver.log")
raise "Stage already launched" if File.exist?(receipt_path) || File.exist?(log)
names = %w[verified-external-validation.rb adapt-correction-templates.rb correction-driver-template-reuse.json correction-template-context.json correction-pilot-driver.rb correction-full-driver.rb verify-correction-pilot.rb commit-corrections.rb prepare-corrected-checkout.rb revalidation-driver.rb verify-revalidation-completion.rb launch-correction-pilot.rb launch-correction-full.rb promote-corrections.rb launch-measurement-stage.rb correction-request-pacing.rb review-request-pacing.rb test-correction-request-pacing.rb test-review-request-pacing.rb paced-correction-driver.rb launch-paced-corrections.rb]
method_root = File.join(__dir__, "experiment-supplemental")
method_commit, method_status = Open3.capture2("git", "-C", method_root, "rev-parse", "HEAD")
raise "New method snapshot unavailable" unless method_status.success?
method_files, method_status = Open3.capture2("git", "-C", method_root, "ls-files")
raise "Cannot enumerate new method snapshot" unless method_status.success?
paths = names.map { |name| File.join(__dir__, name) } + [gate_path, audit_path, cli_path] +
  external.fetch(:paths).keys + method_files.lines(chomp: true).map { |path| File.join(method_root, path) }
original_driver = File.join(__dir__, "correction-#{stage}-driver.rb")
report = {
  "prepared_at" => Time.now.utc.iso8601, "unit" => unit, "stage" => stage,
  "files" => paths.uniq.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
  "gate_path" => gate_path, "gate_sha256" => Digest::SHA256.file(gate_path).hexdigest,
  "audit_report_sha256" => Digest::SHA256.file(audit_path).hexdigest,
  "original_driver" => original_driver, "driver_sha256" => Digest::SHA256.file(original_driver).hexdigest,
  "retained_responses" => retained, "corrections" => corrections,
  "method_commit" => method_commit.strip, "external_validation_excluded_ids" => external.fetch(:excluded),
  "external_validation_registry_sha256" => BeamExternalValidation::REGISTRY_SHA256,
  "reused_pilot_corrections" => stage == "full" ? 16 : 0,
  "proposal_model" => "gpt-6.1-sol", "proposal_effort" => "high", "proposal_workers" => 1,
  "independent_review_model" => "gpt-5.6-luna", "independent_review_effort" => "high", "independent_review_workers" => 1,
  "adjudication_model" => "gpt-6.1-sol", "adjudication_effort" => "xhigh", "adjudication_workers" => 1,
  "adjudication_selection" => "Non-accepting or non-high-confidence independent corrected-source reviews only",
  "not_before" => Time.now.utc.iso8601, "deadline" => "2026-11-06T17:00:00Z",
  "minimum_request_spacing_seconds" => 90, "rate_limit_backoff_seconds" => [600, 1200],
  "maximum_consecutive_429_failures_per_program" => 3,
  "review_cli_path" => cli_path, "review_cli_sha256" => cli.fetch("review_cli_sha256"),
  "path" => "#{File.dirname(cli_path)}:/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "model_workers_source_only" => true, "model_workers_can_compile_or_execute" => false,
  "compilation" => "Existing operator materializer, four workers, local /tmp, no generated-program execution",
  "policy" => "Reuse the previous campaign correction workflow with one-request pacing for proposals and reviews. Retain accepted pilot evidence unchanged; retry only strictly pre-output rate-limit failures. Original source remains untouched until one accepted timing-only commit."
}
if mode == "check"
  puts JSON.pretty_generate(report.reject { |key, _| %w[files retained_responses].include?(key) }.merge("preflight_passed" => true, "model_requests" => 0))
  exit
end
File.write(receipt_path, JSON.pretty_generate(report) + "\n", mode: "wx")
names.each { |name| FileUtils.cp(File.join(__dir__, name), File.join(campaign, name)) }
raise "Correction launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Beam paced timing-only corrections and independent review",
  "--property=WorkingDirectory=#{__dir__}", "--setenv=PATH=#{report.fetch('path')}",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}",
  "/usr/bin/ruby", File.join(__dir__, "paced-correction-driver.rb"), stage)
output, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "MainPID", "-p", "InvocationID")
raise "Cannot inspect correction service" unless status.success?
properties = output.lines.to_h { |line| line.chomp.split("=", 2) }
raise "Correction service did not start" unless properties.fetch("ActiveState") == "active"
activation = { "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties,
  "launch_receipt_sha256" => Digest::SHA256.file(receipt_path).hexdigest, "corrections" => corrections }
File.write(File.join(campaign, "correction-#{stage}-paced-activation.json"), JSON.pretty_generate(activation) + "\n", mode: "wx")
puts JSON.pretty_generate(activation)
