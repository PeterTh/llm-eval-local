# frozen_string_literal: true
require_relative "observer-pipeline-v5/tools/timing_audit/lib/timing_audit"
campaign = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation"
root = "/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium-black-scholes-boundary-sol61-v2"
TimingAudit::AuditVerifier.new(root, "full").run
ids = %w[black-scholes_gpt-6.2-astra-medium_hybrid_r4 black-scholes_gpt-6.2-astra-medium_hybrid_r5]
paths = ids.map { |id| File.join(root, "results", id + ".json") }
raise "Supplemental findings differ" unless paths.all? { |path|
  result = JSON.parse(File.read(path))
  result.fetch("verdict") == "invalid" && result.fetch("confidence") == "high" &&
    result.fetch("issue_categories") == ["incomplete_timed_region"] }
events = Dir[File.join(root, "logs/**/events.jsonl")]
events.each { |path| TimingAudit.verify_static_events!(path) }
paths += [File.join(root, "manifest.yaml"),
  "/home/petert/llm-eval-local/analysis/notes/2026-11-03-winner-validity-audit.md",
  "/home/petert/llm-eval-local/analysis/notes/individual/black-scholes_gpt-6-sol-medium_hybrid_r5.md"]
report = {
  "created_at" => TimingAudit.utc_now, "status" => "awaiting_user_decision", "ids" => ids,
  "technical_finding" => "Both correctly aggregate completed GPU/rank durations but omit fixed-size numerical pricing-table preprocessing. Targeted Sol-6.1/xhigh review classifies this as an incomplete timed region under the literal contract.",
  "policy_conflict" => "Published earlier Black-Scholes implementations retain equivalent untimed fixed-size pricing setup as an explicitly documented workload/timing-scope distinction. Do not silently enforce a different rule for this batch.",
  "decision_requested" => "Preserve established fixed-size-template setup treatment, or require timed preprocessing and investigate affected historical results too.",
  "static_reviews_may_continue" => true, "program_corrections_allowed" => false,
  "benchmarking_allowed" => false, "website_changes_allowed" => false,
  "source_changes" => 0, "program_executions" => 0, "compilation" => 0,
  "evidence_sha256" => paths.to_h { |path| [path, TimingAudit.sha256_file(path)] },
  "citation_note" => "The raw supplemental responses identify reference-specific evidence entries in their finding text but reuse the generated relative path. Those entries refer to the separately pinned supplied sequential reference and must not be treated as generated-source citations. Raw responses remain unchanged; any final derived record must retain that distinction.",
  "format_attempt" => "Initial spotcheck failed during local prompt formatting before model invocation; v2 escapes literal percent signs in the numbered reference and restores them during rendering. Both preparations are retained."
}
path = File.join(campaign, "black-scholes-preprocessing-policy.json")
raise "Policy receipt already exists" if File.exist?(path)
TimingAudit.atomic_write(path, JSON.pretty_generate(report) + "\n")
%w[retain-boundary-policy-hold.rb record-primary-pilot-quality.rb verify-audit-completion.rb].each do |name|
  target = File.join(campaign, name)
  if File.exist?(target) && File.binread(target) != File.binread(File.join(__dir__, name))
    backup = target + ".before-policy-hold"
    raise "Backup already exists" if File.exist?(backup)
    FileUtils.cp(target, backup)
  end
  FileUtils.cp(File.join(__dir__, name), target)
end
puts JSON.pretty_generate(report.reject { |key, _| key == "evidence_sha256" })
