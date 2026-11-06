# frozen_string_literal: true
require_relative 'observer-pipeline-v3/tools/timing_audit/lib/timing_audit'
root = '/home/petert/llm_timing_audit/20261106-terra61-ultra-codex-cross-review-sol61'
boundary = '/home/petert/llm_timing_audit/20261106-terra61-ultra-codex-qtclustering'
campaign = '/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra/evaluation'
id = 'qtclustering_gpt-6.1-terra-ultra_hybrid_r5'
manifest = YAML.safe_load_file(File.join(root, 'manifest.yaml'))
manifest.fetch('cross_review_reconciliation').fetch('input_sha256').each do |path, digest|
  raise 'Original conflicting review changed' unless TimingAudit.sha256_file(path) == digest
end
verifier = TimingAudit::AuditVerifier.new(root, 'full')
verifier.run
result_path = File.join(root, 'results', id + '.json')
result = JSON.parse(File.read(result_path))
raise 'Unresolved overlap needs primary/user adjudication' unless result.fetch('confidence') == 'high' &&
  %w[valid invalid].include?(result.fetch('verdict')) &&
  (result.fetch('verdict') != 'invalid' || result.fetch('timing_only_fix_possible'))
accepted = Dir[File.join(root, 'logs', id, 'attempt-*/metadata.yaml')].map { |path| YAML.safe_load_file(path) }
  .select { |row| row['result_sha256'] == TimingAudit.sha256_file(result_path) }
raise 'Reconciliation model identity differs' unless !accepted.empty? && accepted.all? do |row|
  row.fetch('model') == 'gpt-6.1-sol' && row.fetch('reasoning_effort') == 'xhigh' && row.fetch('static_only_verified')
end
prior = TimingAudit.load_jsonl(File.join(boundary, 'final/decisions.jsonl')).find { |row| row.fetch('program_id') == id }
decision = prior.merge(
  'primary_verdict' => prior.fetch('final_verdict'), 'adjudication_verdict' => result.fetch('verdict'),
  'final_verdict' => result.fetch('verdict'), 'final_confidence' => result.fetch('confidence'),
  'final_issue_categories' => result.fetch('issue_categories'),
  'decision_basis' => 'sol_6_1_cross_review_reconciliation',
  'timing_fix_required' => result.fetch('verdict') == 'invalid', 'timing_review_required' => false
).merge(result.slice('timing_only_fix_possible', 'minimal_fix', 'timed_region', 'semantic_equivalence_basis', 'notes', 'evidence'))
destination = File.join(root, 'final')
raise 'Reconciled final decisions exist' if File.exist?(destination)
TimingAudit.atomic_write(File.join(destination, 'decisions.jsonl'), TimingAudit.dump_jsonl([decision]))
TimingAudit.atomic_write(File.join(destination, 'correction-ids.txt'), decision.fetch('timing_fix_required') ? id + "\n" : '')
TimingAudit.atomic_write(File.join(destination, 'review-ids.txt'), '')
receipt = { 'created_at' => TimingAudit.utc_now, 'records' => 1,
  'final_verdict_counts' => { result.fetch('verdict') => 1 },
  'source_commit' => manifest.fetch('generated_source').fetch('commit'),
  'manifest_sha256' => TimingAudit.sha256_file(File.join(root, 'manifest.yaml')),
  'response_sha256' => TimingAudit.sha256_file(result_path),
  'prior_boundary_decisions_sha256' => TimingAudit.sha256_file(File.join(boundary, 'final/decisions.jsonl')),
  'decisions_sha256' => TimingAudit.sha256_file(File.join(destination, 'decisions.jsonl')),
  'finalizer_sha256' => TimingAudit.sha256_file(__FILE__), 'original_reviews_unchanged' => true,
  'policy' => 'Only the same-source general/QT verdict conflict is reconciled; this accepted stronger-model decision overlays the prior reports without deleting them.' }
TimingAudit.atomic_write(File.join(destination, 'metadata.yaml'), YAML.dump(receipt))
FileUtils.cp(__FILE__, File.join(destination, 'finalizer-snapshot.rb'))
FileUtils.cp(__FILE__, campaign)
initial_verifier = File.join(campaign, 'verify-audit-completion.rb')
FileUtils.cp(initial_verifier, File.join(campaign, 'verify-audit-before-cross-review.rb'))
reuse_path = File.join(__dir__, 'export-driver-template-reuse.json')
reuse = JSON.parse(File.read(reuse_path))
changed = %w[export-completed-batch.rb adapt-export-templates.rb adapt-correction-templates.rb verify-audit-completion.rb]
integration = {
  'prepared_at' => TimingAudit.utc_now, 'initial_export_reuse_sha256' => TimingAudit.sha256_file(reuse_path),
  'initial_export_driver_sha256' => reuse.fetch('drivers').find { |row| row.fetch('file') == 'export-completed-batch.rb' }.fetch('adapted_sha256'),
  'initial_audit_verifier_sha256' => TimingAudit.sha256_file(initial_verifier),
  'files_sha256' => changed.to_h { |name| [name, TimingAudit.sha256_file(File.join(__dir__, name))] },
  'policy' => 'Add only the explicit same-source overlap adjudication to completion, correction selection and compact export; preserve earlier reports and method snapshots.'
}
TimingAudit.atomic_write(File.join(campaign, 'timing-overlap-integration.json'), JSON.pretty_generate(integration) + "\n")
%w[adapt-export-templates.rb export-completed-batch.rb].each { |name| FileUtils.cp(File.join(__dir__, name), campaign) }
puts JSON.pretty_generate(receipt)
