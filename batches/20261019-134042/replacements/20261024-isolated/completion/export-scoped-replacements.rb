# frozen_string_literal: true
require 'json'
require 'open3'
require_relative 'experiment/tools/timing_audit/bin/export_validation_audit'
require_relative 'benchmark-export'
require '/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/release/tools/export_opencode_supplement'

scratch = __dir__
root = '/tmp/deepseek41-opencode-evaluation-20261023.71Tq7a/release'
campaign = '/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high'
amendment = File.join(campaign, 'amendments/20261023-filesystem-isolation')
evidence = File.join(amendment, 'evaluation')
native = '/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-isolated-validation'
audit = '/home/petert/llm_timing_audit/20261024-deepseek41-opencode-isolated'
fixes = '/home/petert/llm_timing_fixes/20261024-deepseek41-opencode-isolated'
base = 'batches/20261019-134042/replacements/20261024-isolated'
batch = File.join(root, base)
selection = { 'evidence_root' => base, 'evaluation' => evidence, 'audit_id' => File.basename(audit),
  'original' => '2c84ee55733daf9fc48a869e5d1f4a068f404f1f', 'pricing' => File.join(evidence, 'pricing'),
  'ids' => File.readlines(File.join(amendment, 'run-ids.txt'), chomp: true).reject(&:empty?).sort }
raise 'Wrong replacement scope' unless selection.fetch('ids').size == 24
report = JSON.parse(File.read(File.join(evidence, 'benchmark-completion-review.json')))
raise 'Benchmark completion not verified' unless report.fetch('verification') == 'passed' && report.fetch('completed') == 23 && report.fetch('all_records_reconciled')
stage = ARGV.fetch(0, 'all')
raise 'Unknown export stage' unless %w[all validation corrections benchmark complete].include?(stage)
if %w[all validation].include?(stage)
  ValidationAuditExport.run(run_dir: native, output_dir: batch, primary: audit, priority: "#{audit}-priority", adjudication: "#{audit}-sol61")
  OpenCodeSupplement.run(root: root, home: '/home/petert', phase: 'audit', batch_id: '20261019-134042', selection: selection)
end
if %w[all corrections].include?(stage)
  TimingCorrectionExport.run(batch_dir: batch, proposal_root: "#{fixes}-proposals", review_root: "#{fixes}-review",
    adjudication_root: "#{fixes}-review-sol61", final_root: "#{fixes}-final",
    validation_run: '/home/petert/llm_para_local_evaluation/20261024-deepseek41-opencode-isolated-corrected',
    original_source: File.join(scratch, 'original-backup'), audit_selection: File.join(batch, 'timing-audit/resolved-selection.json'))
end
if %w[all benchmark].include?(stage)
  BenchmarkBatchExport.run(run_dir: native, batch_dir: batch, conditional_decisions: File.join(batch, 'timing-audit/conditional-decisions.jsonl'))
end
if %w[all complete].include?(stage)
  raise 'Native aggregate failed' unless system(RbConfig.ruby, File.join(scratch, 'local-evaluation-driver.rb'), 'aggregate', "--run-dir=#{native}")
  raise 'Aggregate import failed' unless system(RbConfig.ruby, File.join(root, 'tools/import_batch_aggregate.rb'), "--native-run=#{native}", '--batch=20261019-134042', "--evidence-root=#{base}")
  OpenCodeSupplement.run(root: root, home: '/home/petert', phase: 'complete', batch_id: '20261019-134042', selection: selection)
  FileUtils.cp(__FILE__, evidence)
  FileUtils.cp(__FILE__, File.join(batch, 'completion'))
  receipt = { 'exported_at' => Time.now.utc.iso8601, 'batch' => '20261019-134042', 'records' => 24,
    'benchmarks' => report.fetch('completed'), 'successful' => report.fetch('successful'), 'corrections' => 6,
    'evidence_root' => base, 'release_workspace' => root, 'driver_sha256' => TimingAudit.sha256_file(__FILE__),
    'benchmark_completion_sha256' => TimingAudit.sha256_file(File.join(evidence, 'benchmark-completion-review.json')) }
  File.write(File.join(evidence, 'batch-export.json'), JSON.pretty_generate(receipt) + "\n")
  puts JSON.pretty_generate(receipt)
end
