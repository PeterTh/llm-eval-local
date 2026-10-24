# frozen_string_literal: true

$stdout.sync = true
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/timing_fix"
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/timing_fix_materializer"
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/timing_fix_review"
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/lib/timing_fix_adjudication"
require "/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/experiment/tools/timing_audit/bin/timing_fix_review_reuse"

campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/evaluation"
proposals = "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-proposals"
review = "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-review"
adjudication = "/home/petert/llm_timing_fixes/20261023-deepseek41-opencode-review-sol61"
phase = "verify_pilot_gate"
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(File.join(campaign, "correction-full-progress.json"), JSON.pretty_generate({
    "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
    "driver_sha256" => TimingAudit.sha256_file(__FILE__)
  }.merge(extra)) + "\n")
end

begin
  checkpoint.call
  gate = JSON.parse(File.read(File.join(campaign, "correction-pilot-gate.json")))
  raise "Pilot gate did not pass" unless gate.fetch("passed")
  gate.fetch("input_sha256").each do |path, digest|
    raise "Pilot input changed: #{path}" unless TimingAudit.sha256_file(path) == digest
  end
  pilot_review = gate.fetch("review_root")
  phase = "proposals_full"
  checkpoint.call
  TimingFix::ProposalRunner.new(output_dir: proposals, scope: "full", jobs: 2,
    model: "gpt-6.1-sol", effort: "high").run
  phase = "compile_full"
  checkpoint.call
  summary = File.join(proposals, "materialized/summary-full.yaml")
  unless File.file?(summary)
    TimingFixMaterializer.run(output_dir: proposals, scope: "full", jobs: 4)
  end
  raise "Compilation failures require scoped investigation" unless YAML.safe_load_file(summary).fetch("compile_failures").empty?
  phase = "independent_full_review"
  checkpoint.call
  TimingFixReview::InventoryBuilder.new(proposal_root: proposals, output_dir: review, scope: "full").run unless File.exist?(review)
  unless File.exist?(File.join(review, "reused-reviews.json"))
    TimingFixReviewReuse.run(source: pilot_review, destination: review, model: "gpt-5.6-luna", effort: "high")
  end
  TimingFixReview::Runner.new(output_dir: review, scope: "full", jobs: 16,
    model: "gpt-5.6-luna", effort: "high").run
  phase = "sol61_postfix_adjudication"
  checkpoint.call
  TimingFixAdjudication::InventoryBuilder.new(review_root: review, output_dir: adjudication).run unless File.exist?(adjudication)
  TimingFixAdjudication::Runner.new(output_dir: adjudication, scope: "full", jobs: 2,
    model: "gpt-6.1-sol", effort: "xhigh").run
  disputed = TimingAudit.load_jsonl(File.join(adjudication, "summary-full.jsonl"))
  unresolved = disputed.reject { |row| row.fetch("final_verdict") == "accept" && row.fetch("confidence") == "high" }
  phase = "awaiting_correction_commit_review"
  checkpoint.call("unresolved_ids" => unresolved.map { |row| row.fetch("program_id") },
    "proposals" => proposals, "review" => review, "adjudication" => adjudication)
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
