# frozen_string_literal: true
require "json"
require "time"
$stdout.sync = true
$stderr.sync = true
campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/amendments/20261023-filesystem-isolation/evaluation"
plan = JSON.parse(File.read(File.join(campaign, "campaign.json")))
method = plan.fetch("frozen_pipeline_checkout")
%w[timing_fix timing_fix_materializer timing_fix_review timing_fix_adjudication].each do |name|
  require File.join(method, "tools/timing_audit/lib", name)
end
audit = "/home/petert/llm_timing_audit/20261024-deepseek41-opencode-isolated"
boundary = "#{audit}-qtclustering"
proposals = "/home/petert/llm_timing_fixes/20261024-deepseek41-opencode-isolated-proposals"
review = "/home/petert/llm_timing_fixes/20261024-deepseek41-opencode-isolated-review"
adjudication = "#{review}-sol61"
phase = "verify_final_audit"
checkpoint = lambda do |extra = {}|
  report = { "updated_at" => TimingAudit.utc_now, "phase" => phase,
    "driver_sha256" => TimingAudit.sha256_file(__FILE__) }.merge(extra)
  TimingAudit.atomic_write(File.join(campaign, "correction-full-progress.json"), JSON.pretty_generate(report) + "\n")
  puts JSON.generate(report)
end
begin
  checkpoint.call
  completed = JSON.parse(File.read(File.join(campaign, "audit-completion-review.json")))
  raise "Unresolved timing review" unless completed.fetch("passed") && completed.fetch("unresolved").empty?
  roots = [audit, boundary].select { |r| File.file?(File.join(r, "final/decisions.jsonl")) }
  decisions = roots.flat_map { |r| TimingAudit.load_jsonl(File.join(r, "final/decisions.jsonl")) }.to_h { |r| [r.fetch("program_id"), r] }
  raise "Audit coverage changed" unless decisions.size == completed.fetch("unique_programs")
  expected = decisions.values.select { |r| r["final_verdict"] == "invalid" }.map { |r| r.fetch("program_id") }.sort
  raise "Invalid correction scope" unless !expected.empty? && expected.size <= 16 && (expected - plan.fetch("affected_observations")).empty?
  policy_path = File.join(campaign, "correction-policy.json")
  if File.exist?(policy_path)
    policy = JSON.parse(File.read(policy_path))
    policy.fetch("input_sha256").each { |path, sha| raise "Final decision changed" unless TimingAudit.sha256_file(path) == sha }
  else
    policy = { "created_at" => TimingAudit.utc_now, "corrections" => expected.size, "ids" => expected,
      "input_sha256" => (roots.map { |r| File.join(r, "final/decisions.jsonl") } + [File.join(campaign, "audit-completion-review.json")]).to_h { |p| [p, TimingAudit.sha256_file(p)] },
      "proposal_writer" => "Existing Sol 6.1/high timing-only patch writer",
      "independent_review" => "Luna/high for every patch; Sol 6.1/xhigh only for flagged uncertainty or disagreement",
      "scope_policy" => "The entire affected-only correction set is smaller than the established 16-case pilot cap; review it once, without a duplicate pilot/full pass. Native revalidation is a later gate." }
    TimingAudit.atomic_write(policy_path, JSON.pretty_generate(policy) + "\n")
  end
  phase = "prepare_proposals"
  checkpoint.call("expected" => expected.size)
  TimingFix::InventoryBuilder.new(audit_root: audit, overlay_roots: roots.drop(1),
    source_root: plan.fetch("isolated_source_checkout"), output_dir: proposals,
    context_path: File.join(plan.fetch("validation_run"), "timing-platform-context.txt"), trial_size: 16).run unless File.exist?(proposals)
  raise "Proposal inventory differs" unless TimingAudit.load_jsonl(File.join(proposals, "inventory.jsonl")).map { |r| r.fetch("id") }.sort == expected
  phase = "proposals_full"
  checkpoint.call
  TimingFix::ProposalRunner.new(output_dir: proposals, scope: "full", jobs: 2, model: "gpt-6.1-sol", effort: "high").run
  phase = "compile_full"
  checkpoint.call
  summary = File.join(proposals, "materialized/summary-full.yaml")
  TimingFixMaterializer.run(output_dir: proposals, scope: "full", jobs: 4) unless File.file?(summary)
  raise "Compilation failures" unless YAML.safe_load_file(summary).fetch("compile_failures").empty?
  phase = "independent_full_review"
  checkpoint.call
  TimingFixReview::InventoryBuilder.new(proposal_root: proposals, output_dir: review, scope: "full").run unless File.exist?(review)
  TimingFixReview::Runner.new(output_dir: review, scope: "full", jobs: 4, model: "gpt-5.6-luna", effort: "high").run
  phase = "uncertainty_only_postfix_adjudication"
  checkpoint.call
  TimingFixAdjudication::InventoryBuilder.new(review_root: review, output_dir: adjudication).run unless File.exist?(adjudication)
  TimingFixAdjudication::Runner.new(output_dir: adjudication, scope: "full", jobs: 2, model: "gpt-6.1-sol", effort: "xhigh").run
  disputed = TimingAudit.load_jsonl(File.join(adjudication, "summary-full.jsonl"))
  unresolved = disputed.reject { |r| r.fetch("final_verdict") == "accept" && r.fetch("confidence") == "high" }
  phase = "awaiting_correction_commit_review"
  checkpoint.call("unresolved_ids" => unresolved.map { |r| r.fetch("program_id") }, "proposals" => proposals,
    "review" => review, "adjudication" => adjudication, "corrections" => expected.size)
rescue Exception => error
  stopped = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped, "error" => "#{error.class}: #{error.message}")
  raise
end
