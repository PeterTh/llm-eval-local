# frozen_string_literal: true

$stdout.sync = true
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/timing_fix"
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/timing_fix_materializer"
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/timing_fix_review"
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/timing_fix_adjudication"

campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/evaluation"
audit = "/home/petert/llm_timing_audit/20261023-deepseek41-opencode"
boundary = "#{audit}-qtclustering"
proposals = "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-proposals"
review = "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-review-pilot"
adjudication = "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-review-pilot-sol61"
phase = "verify_final_audits"
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(File.join(campaign, "correction-pilot-progress.json"), JSON.pretty_generate({
    "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
    "driver_sha256" => TimingAudit.sha256_file(__FILE__)
  }.merge(extra)) + "\n")
end

begin
  checkpoint.call
  completed = JSON.parse(File.read(File.join(campaign, "audit-completion-review.json")))
  raise "Audit integrity gate did not pass" unless completed.fetch("passed")
  completed.fetch("input_sha256").each do |path, digest|
    raise "Final audit changed: #{path}" unless TimingAudit.sha256_file(path) == digest
  end
  decisions = {}
  [audit, boundary].each do |root|
    TimingAudit.load_jsonl(File.join(root, "final/decisions.jsonl")).each do |row|
      decisions[row.fetch("program_id")] = row
    end
  end
  raise "Audit coverage mismatch" unless decisions.size == completed.fetch("unique_programs")
  unresolved = decisions.values.select do |row|
    row.fetch("final_verdict") == "ambiguous" || row.fetch("final_confidence") != "high" ||
      (row.fetch("final_verdict") == "invalid" && !row.fetch("timing_only_fix_possible"))
  end
  raise "Unresolved audit decisions: #{unresolved.map { |row| row.fetch('program_id') }.join(', ')}" unless unresolved.empty?
  phase = "prepare_proposals"
  checkpoint.call
  unless File.exist?(proposals)
    TimingFix::InventoryBuilder.new(audit_root: audit, overlay_roots: [boundary],
      source_root: "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/generated", output_dir: proposals,
      context_path: "/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-validation/timing-platform-context.txt",
      trial_size: 16).run
  end
  phase = "proposal_pilot"
  checkpoint.call
  TimingFix::ProposalRunner.new(output_dir: proposals, scope: "trial", jobs: 2,
    model: "gpt-6.1-sol", effort: "high").run
  phase = "compile_pilot"
  checkpoint.call
  summary = File.join(proposals, "materialized/summary-trial.yaml")
  unless File.file?(summary)
    TimingFixMaterializer.run(output_dir: proposals, scope: "trial", jobs: 4)
  end
  raise "Pilot has compilation failures" unless YAML.safe_load_file(summary).fetch("compile_failures").empty?
  phase = "independent_pilot_review"
  checkpoint.call
  TimingFixReview::InventoryBuilder.new(proposal_root: proposals, output_dir: review, scope: "trial").run unless File.exist?(review)
  TimingFixReview::Runner.new(output_dir: review, scope: "full", jobs: 4,
    model: "gpt-5.6-luna", effort: "high").run
  phase = "pilot_sol61_adjudication"
  checkpoint.call
  TimingFixAdjudication::InventoryBuilder.new(review_root: review, output_dir: adjudication).run unless File.exist?(adjudication)
  TimingFixAdjudication::Runner.new(output_dir: adjudication, scope: "full", jobs: 2,
    model: "gpt-6.1-sol", effort: "xhigh").run
  disputed = TimingAudit.load_jsonl(File.join(adjudication, "summary-full.jsonl"))
  rejected = disputed.reject { |row| row.fetch("final_verdict") == "accept" && row.fetch("confidence") == "high" }
  phase = "awaiting_pilot_quality_review"
  checkpoint.call("unresolved_ids" => rejected.map { |row| row.fetch("program_id") },
    "proposals" => proposals, "review" => review, "adjudication" => adjudication)
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
