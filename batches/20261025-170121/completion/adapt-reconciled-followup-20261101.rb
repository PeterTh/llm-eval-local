# frozen_string_literal: true
require_relative "experiment/tools/timing_audit/lib/timing_audit"
require_relative "verified-replicated-work"
resolution = BeamReplicatedWork.verify!
old_proposals = resolution.fetch("prior_proposal_root")
new_proposals = resolution.fetch("proposal_root")
adaptations = {
  "prepare-corrected-checkout.rb" => ["prepare-corrected-checkout-v2.rb", {
    old_proposals => new_proposals,
    "audit-completion-supplemental-review.json" => "audit-completion-replicated-work-review.json",
    "correction-full-progress.json" => "correction-resumed-progress-20261101.json"
  }],
  "commit-corrections.rb" => ["commit-corrections-v2.rb", { old_proposals => new_proposals }],
  "launch-measurement-stage-v2.rb" => ["launch-measurement-stage-v3.rb", {
    'BeamExternalValidation.verify!' => 'BeamExternalValidation.verify!',
    '== 56' => '== replica_resolution.fetch("corrections")',
    'llm-beam10-oc-correction-full-20261031.service' => 'llm-beam10-oc-correction-resumed-20261101.service',
    'correction-full-progress.json' => 'correction-resumed-progress-20261101.json',
    'Exactly 56 timing-corrected programs' => 'Exactly #{replica_resolution.fetch("corrections")} timing-corrected programs'
  }],
  "export-completed-batch-v2.rb" => ["export-completed-batch-v3.rb", { old_proposals => new_proposals }]
}
receipts = adaptations.map do |source_name, (target_name, replacements)|
  source = File.join(__dir__, source_name)
  target = File.join(__dir__, target_name)
  raise "Adapted driver already exists" if File.exist?(target)
  original = File.read(source)
  adapted = original.dup
  replacements.each do |before, after|
    raise "Adaptation marker missing: #{source_name}: #{before}" unless adapted.include?(before)
    adapted = adapted.gsub(before, after)
  end
  marker = "# frozen_string_literal: true\n"
  adapted = adapted.sub(marker, marker + "\nrequire_relative \"verified-replicated-work\"\nreplica_resolution = BeamReplicatedWork.verify!\n")
  if source_name == "commit-corrections.rb"
    marker = 'raise "Correction selection changed" unless'
    adapted = adapted.sub(marker, 'raise "Reconciled correction selection changed" unless expected_ids == replica_resolution.fetch("correction_ids")' + "\n" + marker)
  end
  TimingAudit.atomic_write(target, adapted)
  raise "Syntax check failed: #{target}" unless system(RbConfig.ruby, "-c", target)
  FileUtils.cp(target, BeamExternalValidation::CAMPAIGN)
  { "source" => source, "source_sha256" => TimingAudit.sha256_file(source),
    "target" => target, "target_sha256" => TimingAudit.sha256_file(target),
    "replacements" => replacements }
end
report = { "created_at" => TimingAudit.utc_now, "corrections" => resolution.fetch("corrections"),
  "benchmark_eligible" => resolution.fetch("benchmark_eligible"), "adaptations" => receipts,
  "scope" => "Only correction selection, provenance gate and resume-stage paths changed. Native validation, additional external validation and historical benchmark drivers/configuration remain unchanged." }
output = File.join(BeamExternalValidation::CAMPAIGN, "reconciled-followup-adaptation-20261101.json")
raise "Follow-up adaptation receipt exists" if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, BeamExternalValidation::CAMPAIGN)
puts JSON.pretty_generate(report)
