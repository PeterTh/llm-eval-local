# frozen_string_literal: true
require 'tmpdir'
require_relative 'experiment/tools/timing_audit/bin/export_validation_audit'
require_relative 'artifact/tools/export_fable51_supplement'

root = Dir.mktmpdir('fable51-audit-export-smoke-', '/tmp')
audit = '/home/petert/llm_timing_audit/20261107-fable51-medium'
batch = File.join(root, 'batches', Fable51Supplement::BATCH)
ValidationAuditExport.run(
  run_dir: '/home/petert/llm_para_local_evaluation/20261107-fable51-medium-validation',
  output_dir: batch, primary: audit, priority: audit + '-priority', adjudication: audit + '-sol61'
)
attempts_path = File.join(batch, 'timing-audit/primary/attempts.jsonl')
before = LocalEvalArtifact.read_jsonl(attempts_path)
Fable51Supplement.run(root: root, home: '/home/petert', phase: 'audit')
after = LocalEvalArtifact.read_jsonl(attempts_path).to_h { |row| [[row.fetch('program_id'), row.fetch('attempt')], row] }
before.each do |row|
  retained = after.fetch([row.fetch('program_id'), row.fetch('attempt')])
  raise 'Supplement lost native-export attempt diagnostics' unless row.all? { |key, value| retained[key] == value }
end
selection = JSON.parse(File.read(File.join(batch, 'timing-audit/resolved-selection.json')))
raise 'Resolved scope differs' unless selection.fetch('record_count') == 120 &&
  selection.fetch('verdict_counts') == { 'valid' => 51, 'invalid' => 69 }
summary = JSON.parse(File.read(File.join(batch, 'summary.json')))
raise 'Unexpected audit stage population' unless summary.fetch('timing_audit_records').values.sum == 283
raise 'Unfinished benchmark marked complete' unless summary.fetch('benchmarking_performed') == false
required = %w[
  timing-audit/primary/final-before-platform-reconciliation/decisions.jsonl
  timing-audit/primary/recovery/layout.json
  timing-audit/platform-sol61/target-platform-proof/preprocessing-proof.json
  completion/platform-timing-reconciliation.json
  completion/audit-citation-normalization.json
]
required.each { |relative| raise "Missing preserved evidence: #{relative}" unless File.file?(File.join(batch, relative)) }
files = LocalEvalArtifact.regular_files(root)
raise 'Binary build artifacts exported' if files.any? { |path| path.match?(/\.(?:o|a|so|cubin|ptx)\z/) }
puts JSON.pretty_generate({ 'smoke_root' => root, 'passed' => true, 'validation_records' => 220,
  'audit_unique_programs' => 120, 'audit_responses' => 283, 'timing_corrections' => 69,
  'files' => files.size, 'bytes' => files.sum { |path| File.size(path) },
  'failed_attempt_diagnostics_retained' => before.count { |row| row.key?('exported_response_validation_error') },
  'program_executions' => 0, 'actual_release_modified' => false })
