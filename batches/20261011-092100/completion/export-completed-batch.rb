# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'experiment/tools/timing_audit/bin/export_validation_audit'
require_relative 'benchmark-export'
require_relative 'artifact/tools/export_fable51_supplement'
require_relative 'artifact/tools/export_native_spmv'
require_relative 'artifact/tools/export_timing_revision_evidence'

scratch = __dir__
root = File.join(scratch, 'artifact')
batch_id = '20261011-092100'
batch = File.join(root, 'batches', batch_id)
campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
native = '/home/petert/llm_para_local_evaluation/20261107-fable51-medium-validation'
audit = '/home/petert/llm_timing_audit/20261107-fable51-medium'
validation = JSON.parse(File.read(File.join(campaign, 'validation-completion-review.json')))
report = JSON.parse(File.read(File.join(campaign, 'benchmark-completion-review.json')))
raise 'Benchmark completion not verified' unless report.fetch('verification') == 'passed' &&
  report.fetch('completed') == validation.fetch('passed') && report.fetch('all_records_reconciled')
state, status = Open3.capture2('systemctl', '--user', 'show', 'llm-fable51-medium-benchmark-20261107.service', '--property=ActiveState', '--value')
raise 'Measurements still active' unless status.success? && !%w[active activating deactivating].include?(state.strip)
raise 'Batch already exported' if File.exist?(batch)
raise 'Original validation changed' unless validation.fetch('completed') == 220 &&
  validation.fetch('validation_results_sha256') == TimingAudit.sha256_file(File.join(native, 'validation/all_validation_results.yaml'))
audit_report = JSON.parse(File.read(File.join(campaign, 'audit-completion-review.json')))
raise 'Audit unresolved' unless audit_report.fetch('passed') && audit_report.fetch('unresolved').empty?
extra = audit_report.fetch('decision_roots').drop(2)
raise 'Unsupported extra decision root count' unless extra.size <= 1
ValidationAuditExport.run(run_dir: native, output_dir: batch, primary: audit,
  priority: audit + '-priority', adjudication: audit + '-sol61', supplemental: extra.first)
Fable51Supplement.run(root: root, home: '/home/petert', phase: 'audit')
TimingCorrectionExport.run(batch_dir: batch,
  proposal_root: '/home/petert/llm_timing_fixes/20261107-fable51-medium-proposals-revision1',
  review_root: '/home/petert/llm_timing_fixes/20261107-fable51-medium-review-revision1',
  adjudication_root: '/home/petert/llm_timing_fixes/20261107-fable51-medium-review-revision1-sol61',
  final_root: '/home/petert/llm_timing_fixes/20261107-fable51-medium-final',
  validation_run: '/home/petert/llm_para_local_evaluation/20261107-fable51-medium-corrected',
  original_source: File.join(scratch, 'original-backup'),
  audit_selection: File.join(batch, 'timing-audit/resolved-selection.json'))
BenchmarkBatchExport.run(run_dir: native, batch_dir: batch,
  conditional_decisions: File.join(batch, 'timing-audit/conditional-decisions.jsonl'))
# Claude cumulative native counters are read directly by the established parser;
# the Codex-specific sidecar used by the previous campaign does not apply here.
raise 'Native aggregate failed' unless system(RbConfig.ruby, File.join(scratch, 'local-evaluation-driver.rb'), 'aggregate', "--run-dir=#{native}")
raise 'Aggregate import failed' unless system(RbConfig.ruby, File.join(root, 'tools/import_batch_aggregate.rb'), "--native-run=#{native}", "--batch=#{batch_id}")
spmv = NativeSpmvExport.run(method_root: File.join(scratch, 'experiment'),
  workspace: '/tmp/fable51-spmv-review-20261107-4143246-6l4866', evidence: File.join(campaign, 'spmv-review'),
  destination: File.join(batch, 'validation/spmv-work-count'))
raise 'Native SpMV scope differs' unless spmv.fetch('population') == 20 && spmv.fetch('remaining').zero?
summary_path = File.join(batch, 'summary.json')
summary = JSON.parse(File.read(summary_path))
summary['native_spmv_review'] = {
  'population' => spmv.fetch('population'), 'new_failures' => spmv.fetch('new_failures'),
  'export' => 'validation/spmv-work-count/export.json',
  'export_sha256' => TimingAudit.sha256_file(File.join(batch, 'validation/spmv-work-count/export.json'))
}
TimingAudit.atomic_write(summary_path, JSON.pretty_generate(summary) + "\n")
Fable51Supplement.run(root: root, home: '/home/petert', phase: 'complete')
history_check = JSON.parse(File.read(File.join(campaign, 'correction-history-export-check.json')))
raise 'Correction history exporter changed' unless history_check.fetch('passed') &&
  history_check.fetch('exporter_sha256') == TimingAudit.sha256_file(File.join(root, 'tools/export_timing_revision_evidence.rb'))
history = TimingRevisionEvidenceExport.run(batch_dir: batch, gate_path: File.join(campaign, 'correction-revision-1.json'))
summary = JSON.parse(File.read(summary_path))
summary.fetch('timing_corrections')['revision_history'] = {
  'export' => 'timing-corrections/revision-history/export.json',
  'files' => history.fetch('files'), 'bytes' => history.fetch('bytes')
}
TimingAudit.atomic_write(summary_path, JSON.pretty_generate(summary) + "\n")
%w[correction-history-export-check.json correction-history-export-tests.log
  test-and-retain-correction-history-export.rb correction-export-amendment.json
  retain-correction-export-amendment.rb].each do |name|
  TimingAudit.atomic_write(File.join(batch, 'completion', name), File.binread(File.join(campaign, name)))
end
smoke_path = File.join(campaign, 'audit-export-smoke.json')
smoke = JSON.parse(File.read(smoke_path))
raise 'Audit export smoke gate failed' unless smoke.fetch('passed')
smoke.fetch('checks').each do |check|
  raise 'Export smoke check evidence changed' unless check.fetch('success') &&
    check.fetch('exit_status').zero? && TimingAudit.sha256_file(check.fetch('log')) == check.fetch('log_sha256')
end
raise 'Tested audit exporter changed' unless TimingAudit.sha256_file(File.join(root, 'tools/export_fable51_supplement.rb')) ==
  smoke.fetch('retained_helpers').fetch('export_fable51_supplement.rb')
%w[audit-export-smoke.json audit-export-smoke.log fable-export-regressions.log
  benchmark-eta-regressions.log test-audit-export-smoke.rb retain-audit-export-check.rb
  benchmark-driver-template-reuse.json benchmark-export-template-reuse.json].each do |name|
  TimingAudit.atomic_write(File.join(batch, 'completion', name), File.binread(File.join(campaign, name)))
end
receipt = {
  'exported_at' => TimingAudit.utc_now, 'batch' => batch_id, 'records' => 220,
  'benchmarks' => report.fetch('completed'), 'successful' => report.fetch('successful'),
  'corrections' => report.fetch('timing_fixed_records'), 'release_workspace' => root,
  'completion_report_sha256' => TimingAudit.sha256_file(File.join(campaign, 'benchmark-completion-review.json')),
  'driver_sha256' => TimingAudit.sha256_file(__FILE__),
  'supplement_sha256' => TimingAudit.sha256_file(File.join(root, 'tools/export_fable51_supplement.rb')),
  'generation_evidence_helper_sha256' => TimingAudit.sha256_file(File.join(root, 'tools/fable51_generation_evidence.rb')),
  'policy' => 'Compact native evidence export only. Combined scoring, new-winner analysis, package/site checks and publication are separate gates.'
}
TimingAudit.atomic_write(File.join(campaign, 'batch-export.json'), JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(receipt)
