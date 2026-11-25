# frozen_string_literal: true
require_relative 'observer-pipeline-v5/tools/timing_audit/lib/timing_audit'
root = '/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium-cross-review-sol61'
boundary = '/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium-qtclustering'
campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
id = 'qtclustering_gpt-6.2-sol-medium_hybrid_r3'
manifest = YAML.safe_load_file(File.join(root, 'manifest.yaml'))
manifest.fetch('cross_review_reconciliation').fetch('input_sha256').each do |path, digest|
  raise 'Conflicting review changed' unless TimingAudit.sha256_file(path) == digest
end
raise 'Prior completion changed' unless TimingAudit.sha256_file(File.join(campaign, 'audit-completion-before-cross-review.json')) == manifest.dig('cross_review_reconciliation', 'prior_completion_report_sha256')
TimingAudit::AuditVerifier.new(root, 'full').run
result_path = File.join(root, 'results', id + '.json')
result = JSON.parse(File.read(result_path))
raise 'Unresolved overlap needs primary/user adjudication' unless result.fetch('confidence') == 'high' &&
  %w[valid invalid].include?(result.fetch('verdict')) && (result.fetch('verdict') != 'invalid' || result.fetch('timing_only_fix_possible'))
accepted = Dir[File.join(root, 'logs', id, 'attempt-*/metadata.yaml')].map { |path| YAML.safe_load_file(path) }
  .select { |row| row['result_sha256'] == TimingAudit.sha256_file(result_path) }
raise 'Reconciliation model identity differs' unless !accepted.empty? && accepted.all? { |row|
  row.fetch('model') == 'gpt-6.1-sol' && row.fetch('reasoning_effort') == 'xhigh' && row.fetch('static_only_verified') }
prior = TimingAudit.load_jsonl(File.join(boundary, 'final/decisions.jsonl')).find { |row| row.fetch('program_id') == id }
record = TimingAudit.load_jsonl(File.join(root, 'inventory.jsonl')).fetch(0)
raise 'Reconciliation source mismatch' unless record.fetch('id') == id && record.fetch('source_digest') == prior.fetch('source_digest')
decision = prior.merge(
  'primary_verdict' => prior.fetch('final_verdict'), 'adjudication_verdict' => result.fetch('verdict'),
  'final_verdict' => result.fetch('verdict'), 'final_confidence' => result.fetch('confidence'),
  'final_issue_categories' => result.fetch('issue_categories'),
  'decision_basis' => 'sol_6_1_cross_review_reconciliation',
  'timing_fix_required' => result.fetch('verdict') == 'invalid', 'timing_review_required' => false
).merge(result.slice('timing_only_fix_possible', 'minimal_fix', 'timed_region', 'semantic_equivalence_basis', 'notes', 'evidence'))
destination = File.join(root, 'final')
raise 'Reconciled decisions exist' if File.exist?(destination)
TimingAudit.atomic_write(File.join(destination, 'decisions.jsonl'), TimingAudit.dump_jsonl([decision]))
TimingAudit.atomic_write(File.join(destination, 'correction-ids.txt'), decision.fetch('timing_fix_required') ? id + "\n" : '')
TimingAudit.atomic_write(File.join(destination, 'review-ids.txt'), '')
receipt = { 'created_at' => TimingAudit.utc_now, 'records' => 1,
  'roots' => { 'primary' => boundary, 'priority_review' => nil, 'adjudication' => root },
  'final_verdict_counts' => { result.fetch('verdict') => 1 },
  'source_commit' => manifest.fetch('generated_source').fetch('commit'),
  'manifest_sha256' => TimingAudit.sha256_file(File.join(root, 'manifest.yaml')),
  'response_sha256' => TimingAudit.sha256_file(result_path),
  'prior_boundary_decisions_sha256' => TimingAudit.sha256_file(File.join(boundary, 'final/decisions.jsonl')),
  'decisions_sha256' => TimingAudit.sha256_file(File.join(destination, 'decisions.jsonl')),
  'finalizer_sha256' => TimingAudit.sha256_file(__FILE__), 'original_reviews_unchanged' => true,
  'policy' => 'Only the same-source general/QT conflict is reconciled; stronger-model decision overlays prior retained reports, not a new timing policy.' }
TimingAudit.atomic_write(File.join(destination, 'metadata.yaml'), YAML.dump(receipt))
FileUtils.cp(__FILE__, File.join(destination, 'finalizer-snapshot.rb'))
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(receipt)
