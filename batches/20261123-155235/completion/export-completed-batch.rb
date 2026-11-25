# frozen_string_literal: true
require 'json'
require 'open3'
require_relative 'observer-pipeline-v5/tools/timing_audit/bin/export_validation_audit'
require_relative 'benchmark-export'
require_relative 'artifact/tools/export_gpt62_supplement'
require_relative 'artifact/tools/export_native_spmv'

scratch = __dir__
root = File.join(scratch, 'artifact')
batch_id = '20261123-155235'
batch = File.join(root, 'batches', batch_id)
campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium'
evaluation = File.join(campaign, 'evaluation')
native = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v5'
audit = '/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium'
report = JSON.parse(File.read(File.join(evaluation, 'benchmark-completion-review.json')))
raise 'Benchmark completion not verified' unless report.fetch('verification') == 'passed' &&
  report.fetch('completed') == 439 && report.fetch('all_records_reconciled') && report.fetch('timing_fixed_records') == 24
state, status = Open3.capture2('systemctl', '--user', 'show', 'llm-gpt62-medium-benchmark-20261125.service',
  '--property=ActiveState', '--value')
raise 'Measurements still active' unless status.success? && !%w[active activating deactivating].include?(state.strip)
choice = JSON.parse(File.read(File.join(evaluation, 'default-visible-set-selection.json')))
raise 'Publication discussion unresolved' unless choice.fetch('publication_discussion_resolved') &&
  choice.fetch('selected_visible_count') == 30 && choice.fetch('all_profile_count') == 43
gate = JSON.parse(File.read(File.join(evaluation, 'release-export-check.json')))
raise 'Prepared export has not passed its checks' unless gate.fetch('passed')
gate.fetch('helper_sha256').each do |path, digest|
  raise "Checked exporter changed: #{path}" unless TimingAudit.sha256_file(path) == digest
end
raise 'Batch already exported' if File.exist?(batch)
validation = JSON.parse(File.read(File.join(evaluation, 'validation-completion-review.json')))
raise 'Original validation changed' unless validation.fetch('completed') == 440 && validation.fetch('passed') == 439 &&
  validation.fetch('validation_results_sha256') == TimingAudit.sha256_file(File.join(native, 'validation/all_validation_results.yaml'))

ValidationAuditExport.run(run_dir: native, output_dir: batch, primary: audit,
  priority: audit + '-priority', adjudication: audit + '-sol61')
Gpt62Supplement.run(root: root, home: '/home/petert', phase: 'audit')
TimingCorrectionExport.run(batch_dir: batch,
  proposal_root: '/home/petert/llm_timing_fixes/20261125-gpt62-astra-sol-medium-proposals',
  review_root: '/home/petert/llm_timing_fixes/20261125-gpt62-astra-sol-medium-review',
  adjudication_root: '/home/petert/llm_timing_fixes/20261125-gpt62-astra-sol-medium-review-sol61',
  final_root: '/home/petert/llm_timing_fixes/20261125-gpt62-astra-sol-medium-final',
  validation_run: '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-corrected',
  original_source: File.join(scratch, 'original-backup'),
  audit_selection: File.join(batch, 'timing-audit/resolved-selection.json'))
BenchmarkBatchExport.run(run_dir: native, batch_dir: batch,
  conditional_decisions: File.join(batch, 'timing-audit/conditional-decisions.jsonl'))
raise 'Native aggregate failed' unless system(RbConfig.ruby, File.join(scratch, 'local-evaluation-driver.rb'),
  'aggregate', "--run-dir=#{native}", "--codex-usage=#{File.join(campaign, 'codex-usage.jsonl')}")
raise 'Aggregate import failed' unless system(RbConfig.ruby, File.join(root, 'tools/import_batch_aggregate.rb'),
  "--native-run=#{native}", "--batch=#{batch_id}")
spmv = NativeSpmvExport.run(method_root: File.join(scratch, 'observer-pipeline-v5'),
  workspace: '/tmp/gpt62-medium-spmv-review-20261125-829313-s2ppjr',
  evidence: File.join(evaluation, 'spmv-review'), destination: File.join(batch, 'validation/spmv-work-count'))
raise 'Native SpMV scope differs' unless spmv.fetch('population') == 40 && spmv.fetch('remaining').zero? && spmv.fetch('new_failures').zero?
summary_path = File.join(batch, 'summary.json')
summary = JSON.parse(File.read(summary_path))
summary['native_spmv_review'] = {
  'population' => spmv.fetch('population'), 'new_failures' => spmv.fetch('new_failures'),
  'export' => 'validation/spmv-work-count/export.json',
  'export_sha256' => TimingAudit.sha256_file(File.join(batch, 'validation/spmv-work-count/export.json'))
}
TimingAudit.atomic_write(summary_path, JSON.pretty_generate(summary) + "\n")
Gpt62Supplement.run(root: root, home: '/home/petert', phase: 'complete')
receipt = {
  'exported_at' => TimingAudit.utc_now, 'batch' => batch_id, 'records' => 440,
  'benchmarks' => report.fetch('completed'), 'successful' => report.fetch('successful'),
  'corrections' => report.fetch('timing_fixed_records'), 'release_workspace' => root,
  'completion_report_sha256' => TimingAudit.sha256_file(File.join(evaluation, 'benchmark-completion-review.json')),
  'driver_sha256' => TimingAudit.sha256_file(__FILE__),
  'supplement_sha256' => TimingAudit.sha256_file(File.join(root, 'tools/export_gpt62_supplement.rb')),
  'generation_evidence_helper_sha256' => TimingAudit.sha256_file(File.join(root, 'tools/gpt62_generation_evidence.rb')),
  'policy' => 'Compact evidence export only. Original observer-continuation receipts/method layouts, combined scoring, winner reviews, package/site verification and publication remain separate required gates.'
}
TimingAudit.atomic_write(File.join(evaluation, 'batch-export.json'), JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, evaluation)
puts JSON.pretty_generate(receipt)
