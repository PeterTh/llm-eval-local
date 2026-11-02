# frozen_string_literal: true
$stdout.sync = true
require "open3"
require_relative "experiment/tools/timing_audit/bin/timing_priority_review"
require_relative "review-request-pacing"

mode = ARGV.fetch(0)
raise "Expected prepare or run" unless ARGV.size == 1 && %w[prepare run].include?(mode)
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
output = primary + "-supplemental-20261031"
receipt_path = File.join(campaign, "audit-supplemental-20261031-launch.json")

if mode == "prepare"
  raise "Supplemental already prepared" if File.exist?(output) || File.exist?(receipt_path)
  gate_path = File.join(campaign, "audit-completion-review.json")
  gate = JSON.parse(File.read(gate_path))
  selection_path = File.join(__dir__, "audit-supplemental-selection-20261031.jsonl")
  selected = TimingAudit.load_jsonl(selection_path).map { |row| row.fetch("program_id") }.sort
  raise "Wrong unresolved selection" unless !gate.fetch("passed") && gate.fetch("unresolved").map { |row| row.fetch("program_id") }.sort == selected
  gate.fetch("input_sha256").each { |path, sha| raise "Gate input changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
  fable = JSON.parse(File.read("/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/progress.json"))
  raise "Fable not paused" unless fable.values_at("status", "completed", "active_id") == ["quota_paused", 194, nil]
  raise "Fable STOP missing" unless File.file?("/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/STOP")
  pids, status = Open3.capture2("pgrep", "-u", "llmtest")
  raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
  %w[llm-fable51-generation-20261011-092100.service llm-beam10-oc-timing-full-resume-20261031.service].each do |unit|
    state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
    raise "Competing activity: #{unit}" unless status.success? && state.strip == "inactive"
  end
  cli = JSON.parse(File.read(File.join(campaign, "audit-pilot-launch.json")))
  cli_path = cli.fetch("review_cli_path")
  raise "Pinned CLI changed" unless TimingAudit.sha256_file(cli_path) == cli.fetch("review_cli_sha256")
  context_path = File.join(campaign, "audit-supplemental-context-20261031.txt")
  context = File.read(File.join(__dir__, "timing-platform-context.txt")) + "\n" + File.read(File.join(__dir__, "audit-supplemental-focus-20261031.txt"))
  raise "Context already retained" if File.exist?(context_path)
  TimingAudit.atomic_write(context_path, context)
  TimingPriorityReview.prepare_supplemental(main_root: primary, output_dir: output,
    selection_path: selection_path, context_path: context_path, model: "gpt-6.1-sol")
  retained = Dir[primary + "{,-priority,-sol61,-qtclustering,-qtclustering-sol61}/results/*.json"].sort.to_h { |path| [path, TimingAudit.sha256_file(path)] }
  raise "Wrong accepted parent count" unless retained.size == 218
  snapshot = File.join(output, "prior-final")
  FileUtils.cp_r(File.join(primary, "final"), snapshot)
  files = [__FILE__, selection_path, File.join(__dir__, "audit-supplemental-focus-20261031.txt"), File.join(__dir__, "review-request-pacing.rb"), gate_path, context_path, cli_path]
  receipt = { "prepared_at" => TimingAudit.utc_now, "selected_ids" => selected,
    "root" => output, "parent_root" => primary, "prior_gate_sha256" => TimingAudit.sha256_file(gate_path),
    "files" => files.to_h { |path| [path, TimingAudit.sha256_file(path)] },
    "retained_results" => retained, "prior_final" => Dir[File.join(snapshot, "*")].select { |p| File.file?(p) }.to_h { |path| [path, TimingAudit.sha256_file(path)] },
    "model" => "gpt-6.1-sol", "effort" => "xhigh", "workers" => 1,
    "minimum_request_spacing_seconds" => 90, "source_only" => true,
    "review_cli_path" => cli_path, "review_cli_sha256" => cli.fetch("review_cli_sha256"),
    "policy" => "Focused independent adjudication of exactly the two unresolved cases, preserving all accepted reviews and prior final decisions; no generated-code execution or algorithmic repair." }
  TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
  [__FILE__, selection_path, File.join(__dir__, "audit-supplemental-focus-20261031.txt")].each { |path| FileUtils.cp(path, campaign) }
  puts JSON.pretty_generate(receipt.reject { |key, _| %w[retained_results prior_final files].include?(key) })
  exit
end

receipt = JSON.parse(File.read(receipt_path))
%w[files retained_results prior_final].each do |key|
  receipt.fetch(key).each { |path, sha| raise "Retained input changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
end
ENV["PATH"] = "#{File.dirname(receipt.fetch('review_cli_path'))}:/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin"
BeamReviewPacing.next_request = Time.now
BeamReviewPacing.deadline = Time.iso8601("2026-11-06T17:00:00Z")
BeamReviewPacing.progress_path = File.join(campaign, "audit-supplemental-20261031-progress.json")
BeamReviewPacing.recoveries = []
TimingAudit::AuditRunner.prepend(BeamReviewPacing::Dispatch)
begin
  TimingAudit::AuditRunner.new(output_dir: output, scope: "full", jobs: 1, model: "gpt-6.1-sol", effort: "xhigh", retries: 1).run
  receipt.fetch("retained_results").each { |path, sha| raise "Prior accepted review changed" unless TimingAudit.sha256_file(path) == sha }
  BeamReviewPacing.checkpoint("awaiting_supplemental_quality_review")
rescue Exception => error
  BeamReviewPacing.checkpoint("stopped", "error" => "#{error.class}: #{error.message}")
  raise
end
