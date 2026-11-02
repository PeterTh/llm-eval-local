# frozen_string_literal: true
require_relative "experiment/tools/timing_audit/bin/timing_finalize_audit"
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
supplemental = primary + "-supplemental-communication-20261031"
receipt = JSON.parse(File.read(File.join(campaign, "audit-supplemental-communication-20261031-launch.json")))
%w[files retained_results prior_final].each do |key|
  receipt.fetch(key).each { |path, sha| raise "Retained evidence changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
end
prior = File.join(supplemental, "prior-final/decisions.jsonl")
raise "Already re-finalized" unless TimingAudit.sha256_file(prior) == TimingAudit.sha256_file(File.join(primary, "final/decisions.jsonl"))
TimingAudit::AuditVerifier.new(supplemental, "full").run
results = Dir[File.join(supplemental, "results/*.json")].map { |path| JSON.parse(File.read(path)) }
raise "Wrong supplemental coverage" unless results.map { |r| r.fetch("program_id") }.sort == receipt.fetch("selected_ids").sort
raise "Supplemental unresolved" unless results.all? { |r| r.fetch("confidence") == "high" && r.fetch("verdict") != "ambiguous" && (r.fetch("verdict") != "invalid" || r.fetch("timing_only_fix_possible")) }
TimingFinalizeAudit.run(main_root: primary, priority_root: primary + "-priority",
  adjudication_root: primary + "-sol61", supplemental_root: supplemental)
load File.join(__dir__, "verify-audit-supplemental-completion.rb")
FileUtils.cp(__FILE__, campaign)
