# frozen_string_literal: true
require_relative 'experiment/tools/timing_audit/bin/timing_finalize_audit'

campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
primary = '/home/petert/llm_timing_audit/20261107-fable51-medium'
root = primary + '-platform-sol61'
receipt_path = File.join(campaign, 'platform-timing-reconciliation.json')
raise 'Platform review already reconciled' if File.exist?(receipt_path)
ids = %w[cholesky_claude-fable-5.1-cc-medium_mpi_r2 cholesky_claude-fable-5.1-cc-medium_mpi_r5]
selection = TimingAudit.load_jsonl(File.join(root, 'supplemental-selection.jsonl'))
raise 'Unexpected platform selection' unless selection.map { |row| row.fetch('program_id') } == ids
TimingAudit::AuditVerifier.new(root, 'full').run
results = selection.to_h do |selected|
  id = selected.fetch('program_id')
  prior_path = File.join(primary + '-sol61', 'results', id + '.json')
  raise 'Original uncertain review changed' unless TimingAudit.sha256_file(prior_path) == selected.fetch('prior_response_sha256')
  result_path = File.join(root, 'results', id + '.json')
  result = JSON.parse(File.read(result_path))
  raise 'Platform uncertainty remains; primary/user adjudication required' unless result.fetch('confidence') == 'high' &&
    %w[valid invalid].include?(result.fetch('verdict')) && (result.fetch('verdict') != 'invalid' || result.fetch('timing_only_fix_possible'))
  accepted = Dir[File.join(root, 'logs', id, 'attempt-*/metadata.yaml')].map { |path| YAML.safe_load_file(path) }
    .select { |row| row['result_sha256'] == TimingAudit.sha256_file(result_path) }
  raise 'Follow-up identity not verified' unless !accepted.empty? && accepted.all? { |row|
    row.fetch('model') == 'gpt-6.1-sol' && row.fetch('reasoning_effort') == 'xhigh' && row.fetch('static_only_verified') }
  [id, result]
end
original_decisions = File.join(primary, 'final/decisions.jsonl')
old_rows = TimingAudit.load_jsonl(original_decisions).to_h { |row| [row.fetch('program_id'), row] }
raise 'Final records no longer require uncertainty review' unless ids.all? { |id|
  old_rows.fetch(id).fetch('final_verdict') == 'ambiguous' || old_rows.fetch(id).fetch('final_confidence') != 'high' }
backup = File.join(primary, 'final-before-platform-reconciliation')
raise 'Original final backup already exists' if File.exist?(backup)
FileUtils.cp_r(File.join(primary, 'final'), backup)
TimingFinalizeAudit.run(main_root: primary, priority_root: primary + '-priority', adjudication_root: primary + '-sol61', supplemental_root: root)
new_rows = TimingAudit.load_jsonl(original_decisions).to_h { |row| [row.fetch('program_id'), row] }
raise 'Unrelated final decisions changed' unless old_rows.keys.sort == new_rows.keys.sort &&
  old_rows.reject { |key, _| ids.include?(key) } == new_rows.reject { |key, _| ids.include?(key) }
raise 'Resolved decision differs from model response' unless results.all? { |id, result| new_rows.fetch(id).fetch('final_verdict') == result.fetch('verdict') }
report = {
  'reconciled_at' => TimingAudit.utc_now, 'program_ids' => ids,
  'cases' => ids.map { |id| { 'program_id' => id,
    'prior_verdict' => old_rows.fetch(id).fetch('final_verdict'), 'prior_confidence' => old_rows.fetch(id).fetch('final_confidence'),
    'final_verdict' => results.fetch(id).fetch('verdict'),
    'original_review_sha256' => TimingAudit.sha256_file(File.join(primary + '-sol61', 'results', id + '.json')),
    'followup_response_sha256' => TimingAudit.sha256_file(File.join(root, 'results', id + '.json')) } },
  'manifest_sha256' => TimingAudit.sha256_file(File.join(root, 'manifest.yaml')),
  'preprocessing_proof_sha256' => selection.first.fetch('preprocessing_proof_sha256'),
  'prior_final_decisions_sha256' => TimingAudit.sha256_file(File.join(backup, 'decisions.jsonl')),
  'resolved_final_decisions_sha256' => TimingAudit.sha256_file(original_decisions),
  'unchanged_final_records' => old_rows.size - ids.size, 'original_reviews_preserved' => true,
  'policy' => 'Existing timing contract; only previously unresolved cases are finalized using additional static target-platform evidence and high-confidence Sol-6.1 reviews. No source changes or program runs.'
}
TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report)
