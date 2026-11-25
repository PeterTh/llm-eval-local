# frozen_string_literal: true
require_relative 'observer-pipeline-v5/tools/timing_audit/lib/timing_audit'
campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
root = '/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium-cross-review-sol61'
proposals = '/home/petert/llm_timing_fixes/20261125-gpt62-astra-sol-medium-proposals'
progress_path = File.join(campaign, 'correction-pilot-progress.json')
progress = JSON.parse(File.read(progress_path))
raise 'Unexpected stopped stage' unless progress.values_at('phase', 'stopped_phase') == %w[stopped prepare_proposals] && progress.fetch('error') == 'KeyError: key not found: "roots"'
raise 'Any proposals already started' if File.exist?(proposals)
receipt_path = File.join(campaign, 'correction-root-binding-repair.json')
raise 'Repair already recorded' if File.exist?(receipt_path)
metadata_path = File.join(root, 'final/metadata.yaml')
metadata = YAML.safe_load_file(metadata_path)
raise 'Unexpected root binding' if metadata.key?('roots')
decisions_path = File.join(root, 'final/decisions.jsonl')
decisions_sha = TimingAudit.sha256_file(decisions_path)
raise 'Scientific decisions changed' unless metadata.fetch('decisions_sha256') == decisions_sha
before = TimingAudit.sha256_file(metadata_path)
backup = File.join(root, 'final/metadata-before-root-binding.yaml')
raise 'Metadata backup exists' if File.exist?(backup)
FileUtils.cp(metadata_path, backup)
metadata['roots'] = { 'primary' => '/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium-qtclustering',
  'priority_review' => nil, 'adjudication' => root }
TimingAudit.atomic_write(metadata_path, YAML.dump(metadata))
FileUtils.cp(progress_path, File.join(campaign, 'correction-pilot-progress-before-root-binding.json'))
audit_path = File.join(campaign, 'audit-completion-review.json')
audit_backup = File.join(campaign, 'audit-completion-before-root-binding.json')
raise 'Audit backup exists' if File.exist?(audit_backup)
old_audit_sha = TimingAudit.sha256_file(audit_path)
FileUtils.mv(audit_path, audit_backup)
raise 'Completion reverification failed' unless system('/usr/bin/ruby', File.join(__dir__, 'verify-audit-completion.rb'))
audit = JSON.parse(File.read(audit_path))
raise 'Audit changed scientifically' unless audit.fetch('passed') && audit.fetch('verdicts') == JSON.parse(File.read(audit_backup)).fetch('verdicts') && audit.fetch('verdicts').fetch('invalid') == 24 && TimingAudit.sha256_file(decisions_path) == decisions_sha
new_audit_sha = TimingAudit.sha256_file(audit_path)
# Only refresh the provenance pointer in prepared-helper receipts. Their helper
# bytes, counts, decision roots, timing policy and measurement configuration stay fixed.
%w[correction-template-context.json benchmark-driver-template-reuse.json].each do |name|
  scratch_path = File.join(__dir__, name)
  retained_path = File.join(campaign, name)
  data = JSON.parse(File.read(scratch_path))
  raise 'Unexpected prepared receipt' unless data.fetch('audit_report_sha256') == old_audit_sha && File.binread(scratch_path) == File.binread(retained_path)
  FileUtils.cp(retained_path, File.join(campaign, name.sub(/\.json\z/, '-before-root-binding.json')))
  data['audit_report_sha256'] = new_audit_sha
  data['audit_metadata_provenance_amendment'] = { 'previous_report_sha256' => old_audit_sha,
    'reason' => 'Add missing audit-root handoff metadata; scientific decisions and helper bytes unchanged.' }
  TimingAudit.atomic_write(scratch_path, JSON.pretty_generate(data) + "\n")
  FileUtils.cp(scratch_path, retained_path)
end
receipt = { 'repaired_at' => TimingAudit.utc_now, 'metadata_before_sha256' => before,
  'metadata_after_sha256' => TimingAudit.sha256_file(metadata_path), 'decisions_sha256' => decisions_sha,
  'audit_report_before_sha256' => old_audit_sha, 'audit_report_after_sha256' => new_audit_sha,
  'prior_model_calls' => 0, 'program_changes' => 0, 'program_executions' => 0,
  'policy' => 'Established metadata-only handoff repair, identical to the earlier Terra Ultra case. Original metadata/progress/report preserved. No scientific decision or source changed, no model call repeated.' }
TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(receipt)
