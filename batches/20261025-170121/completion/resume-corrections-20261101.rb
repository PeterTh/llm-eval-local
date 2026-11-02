# frozen_string_literal: true
$stdout.sync = true
require "open3"
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix"
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix_materializer"
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix_review"
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix_adjudication"
require_relative "verified-replicated-work"
require_relative "correction-request-pacing"

campaign = BeamExternalValidation::CAMPAIGN
unit = "llm-beam10-oc-correction-resumed-20261101.service"
receipt_path = File.join(campaign, "correction-resumed-launch-20261101.json")
mode = ARGV.fetch(0)
raise "Use launch|run" unless ARGV.size == 1 && %w[launch run].include?(mode)
resolution = BeamReplicatedWork.verify!
proposals = resolution.fetch("proposal_root")
review = "/home/petert/llm_timing_fixes/20261030-beam10-opencode-review"
adjudication = "/home/petert/llm_timing_fixes/20261030-beam10-opencode-review-sol61"
require_relative "timing-fix-review-reuse-frozen"
gate_path = File.join(campaign, "correction-pilot-gate.json")
gate = JSON.parse(File.read(gate_path))
raise "Original pilot did not pass" unless gate.fetch("passed") && gate.fetch("unresolved_ids").empty?
gate.fetch("input_sha256").each { |path, sha| raise "Pilot evidence changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
if mode == "launch"
  raise "Reconciled correction already launched" if File.exist?(receipt_path) || File.exist?(review) || File.exist?(adjudication)
  %w[llm-beam10-oc-replicated-work-sol61-20261101.service llm-beam10-oc-correction-full-20261031.service llm-fable51-generation-20261011-092100.service].each do |prior_unit|
    state, status = Open3.capture2("systemctl", "--user", "show", prior_unit, "-p", "ActiveState", "--value")
    raise "Competing stage active: #{prior_unit}" unless status.success? && state.strip == "inactive"
  end
  pids, status = Open3.capture2("pgrep", "-u", "llmtest")
  raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
  old_receipt_path = File.join(campaign, "correction-full-launch.json")
  old = JSON.parse(File.read(old_receipt_path))
  old.fetch("files").each { |path, sha| raise "Frozen method changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
  cli = JSON.parse(File.read(File.join(campaign, "audit-pilot-launch.json")))
  raise "CLI changed" unless TimingAudit.sha256_file(cli.fetch("review_cli_path")) == cli.fetch("review_cli_sha256")
  extra_paths = [__FILE__, old_receipt_path, gate_path,
    File.join(campaign, "replicated-work-correction-selection-20261101.json"),
    File.join(__dir__, "verified-replicated-work.rb"), File.join(__dir__, "timing-fix-review-reuse-frozen.rb")]
  previous = JSON.parse(File.read(File.join(campaign, "replicated-work-sol61-review-progress-20261101.json")))
  raise "Targeted adjudication incomplete" unless previous.fetch("phase") == "awaiting_replicated_work_review"
  log = File.join(campaign, "correction-resumed-driver-20261101.log")
  raise "Resume log exists" if File.exist?(log)
  receipt = { "prepared_at" => TimingAudit.utc_now, "unit" => unit,
    "files" => old.fetch("files").merge(extra_paths.to_h { |path| [path, TimingAudit.sha256_file(path)] }),
    "retained_responses" => old.fetch("retained_responses"),
    "proposal_root" => proposals, "corrections" => resolution.fetch("corrections"),
    "proposal_requests" => 0, "reused_proposals" => resolution.fetch("reused_proposals"),
    "pilot_review_reuse_ids" => resolution.fetch("pilot_review_reuse_ids"),
    "new_independent_correction_reviews" => resolution.fetch("new_independent_correction_reviews"),
    "workers" => 1, "minimum_request_spacing_seconds" => 90,
    "not_before" => [Time.now, Time.iso8601(previous.fetch("next_request_not_before"))].max.utc.iso8601,
    "deadline" => "2026-11-06T17:00:00Z", "source_only_model_reviews" => true,
    "compile_only_operator_check" => true, "source_unchanged" => true,
    "path" => "#{File.dirname(cli.fetch('review_cli_path'))}:/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
    "policy" => "Omit accepted complete-result replicas; reuse exact applicable proposals and pilot reviews. Compile selected patches in local /tmp; Luna checks only previously unreviewed corrections, Sol adjudicates only unresolved reviews." }
  TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
  extra_paths.select { |path| File.dirname(path) == __dir__ }.each { |path| FileUtils.cp(path, campaign) }
  raise "Resume launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
    "--description=Beam timing corrections after complete-result replica reconciliation",
    "--property=WorkingDirectory=#{__dir__}", "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}",
    "/usr/bin/ruby", __FILE__, "run")
  puts JSON.pretty_generate(receipt.except("files", "retained_responses"))
  exit
end
receipt = JSON.parse(File.read(receipt_path))
%w[files retained_responses].each { |key| receipt.fetch(key).each { |path, sha| raise "Resume input changed: #{path}" unless TimingAudit.sha256_file(path) == sha } }
ENV["PATH"] = receipt.fetch("path")
BeamReviewPacing.next_request = Time.iso8601(receipt.fetch("not_before"))
BeamReviewPacing.deadline = Time.iso8601(receipt.fetch("deadline"))
BeamReviewPacing.progress_path = File.join(campaign, "correction-resumed-paced-progress-20261101.json")
BeamReviewPacing.recoveries = []
TimingFixReview::Runner.prepend(BeamCorrectionPacing::Review)
TimingFixAdjudication::Runner.prepend(BeamCorrectionPacing::Adjudication)
phase = "verify_reused_proposals"
checkpoint = lambda do |details = {}|
  TimingAudit.atomic_write(File.join(campaign, "correction-resumed-progress-20261101.json"), JSON.pretty_generate({
    "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
    "driver_sha256" => TimingAudit.sha256_file(__FILE__), "corrections" => resolution.fetch("corrections")
  }.merge(details)) + "\n")
end
begin
  checkpoint.call
  TimingFix::ProposalVerifier.new(proposals, "full").run
  phase = "compile_full"
  checkpoint.call
  summary = File.join(proposals, "materialized/summary-full.yaml")
  TimingFixMaterializer.run(output_dir: proposals, scope: "full", jobs: 4) unless File.file?(summary)
  compiled = YAML.safe_load_file(summary)
  raise "Compilation requires investigation" unless compiled.fetch("compile_failures").empty? && compiled.fetch("compile_successes") == resolution.fetch("corrections")
  phase = "independent_full_review"
  checkpoint.call
  TimingFixReview::InventoryBuilder.new(proposal_root: proposals, output_dir: review, scope: "full").run unless File.exist?(review)
  TimingFixReviewReuse.run(source: gate.fetch("review_root"), destination: review, model: "gpt-5.6-luna", effort: "high", only_ids: resolution.fetch("pilot_review_reuse_ids")) unless File.exist?(File.join(review, "reused-reviews.json"))
  TimingFixReview::Runner.new(output_dir: review, scope: "full", jobs: 1, model: "gpt-5.6-luna", effort: "high", retries: 1).run
  phase = "sol61_postfix_adjudication"
  checkpoint.call
  TimingFixAdjudication::InventoryBuilder.new(review_root: review, output_dir: adjudication).run unless File.exist?(adjudication)
  TimingFixAdjudication::Runner.new(output_dir: adjudication, scope: "full", jobs: 1, model: "gpt-6.1-sol", effort: "xhigh", retries: 1).run
  disputed = TimingAudit.load_jsonl(File.join(adjudication, "summary-full.jsonl"))
  unresolved = disputed.reject { |row| row.values_at("final_verdict", "confidence") == ["accept", "high"] }
  phase = "awaiting_correction_commit_review"
  checkpoint.call("unresolved_ids" => unresolved.map { |row| row.fetch("program_id") }, "proposals" => proposals, "review" => review, "adjudication" => adjudication)
  BeamReviewPacing.checkpoint("awaiting_operator_quality_review", "stage" => "reconciled_full")
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  BeamReviewPacing.checkpoint("stopped", "stage" => "reconciled_full", "error" => "#{error.class}: #{error.message}")
  raise
end
