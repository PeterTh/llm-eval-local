# frozen_string_literal: true
require_relative "experiment/tools/timing_audit/lib/timing_audit"
require_relative "verified-final-replica-selection"
resolution = BeamFinalReplicaSelection.verify!
old = BeamReplicatedWork.verify!
adaptations = {
  "prepare-corrected-checkout-v2.rb" => "prepare-corrected-checkout-v3.rb",
  "commit-corrections-v2.rb" => "commit-corrections-v3.rb",
  "launch-measurement-stage-v3.rb" => "launch-measurement-stage-v4.rb",
  "export-completed-batch-v3.rb" => "export-completed-batch-v4.rb"
}
receipts = adaptations.map do |source_name, target_name|
  source = File.join(__dir__, source_name)
  target = File.join(__dir__, target_name)
  raise "Final driver already exists" if File.exist?(target)
  body = File.read(source)
  replacements = {
    'require_relative "verified-replicated-work"' => 'require_relative "verified-final-replica-selection"',
    'BeamReplicatedWork.verify!' => 'BeamFinalReplicaSelection.verify!',
    old.fetch("proposal_root") => resolution.fetch("proposal_root"),
    'audit-completion-replicated-work-review.json' => 'audit-completion-final-replica-review.json',
    '"/home/petert/llm_timing_fixes/20261030-beam10-opencode-review"' => resolution.fetch("review_root").inspect,
    '"/home/petert/llm_timing_fixes/20261030-beam10-opencode-review-sol61"' => resolution.fetch("adjudication_root").inspect
  }
  replacements.each { |before, after| body = body.gsub(before, after) }
  raise "Final driver gate missing" unless body.include?('replica_resolution = BeamFinalReplicaSelection.verify!')
  TimingAudit.atomic_write(target, body)
  raise "Syntax failed" unless system(RbConfig.ruby, "-c", target)
  FileUtils.cp(target, BeamExternalValidation::CAMPAIGN)
  { "source" => source, "source_sha256" => TimingAudit.sha256_file(source),
    "target" => target, "target_sha256" => TimingAudit.sha256_file(target) }
end
report = { "created_at" => TimingAudit.utc_now, "corrections" => resolution.fetch("corrections"),
  "benchmark_eligible" => resolution.fetch("benchmark_eligible"), "adaptations" => receipts,
  "scope" => "Final verified strict correction subset only; native validation and all benchmark settings unchanged." }
path = File.join(BeamExternalValidation::CAMPAIGN, "final-replica-followup-adaptation-20261101.json")
raise "Final adaptation receipt exists" if File.exist?(path)
TimingAudit.atomic_write(path, JSON.pretty_generate(report) + "\n")
%w[adapt-final-replica-followup-20261101.rb verified-final-replica-selection.rb].each { |name| FileUtils.cp(File.join(__dir__, name), BeamExternalValidation::CAMPAIGN) }
puts JSON.pretty_generate(report)
