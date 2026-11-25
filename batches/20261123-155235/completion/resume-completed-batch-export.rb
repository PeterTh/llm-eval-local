# frozen_string_literal: true
require 'json'
require 'open3'
require 'digest'
require 'time'
require_relative 'artifact/tools/export_gpt62_supplement'
require_relative 'artifact/tools/export_native_spmv'

runtime = __dir__
root = File.join(runtime, 'artifact')
batch_id = '20261123-155235'
batch = File.join(root, 'batches', batch_id)
evaluation = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
sha = ->(path) { Digest::SHA256.file(path).hexdigest }
gate_path = File.join(evaluation, 'release-export-check.json')
gate = JSON.parse(File.read(gate_path))
raise 'Initial export gate failed' unless gate.fetch('passed')
changed_helper = File.join(root, 'tools/export_native_spmv.rb')
gate.fetch('helper_sha256').each do |path, digest|
  next if path == changed_helper
  raise "Unexpected exporter change: #{path}" unless sha.call(path) == digest
end
baseline_helper = '/home/petert/llm-eval-local/tools/export_native_spmv.rb'
raise 'Unbound original SpMV exporter' unless sha.call(baseline_helper) == gate.fetch('helper_sha256').fetch(changed_helper)
benchmark_path = File.join(evaluation, 'benchmark-completion-review.json')
benchmark = JSON.parse(File.read(benchmark_path))
raise 'Benchmark not complete' unless benchmark.fetch('verification') == 'passed' && benchmark.fetch('completed') == 439
state, status = Open3.capture2('systemctl', '--user', 'show', 'llm-gpt62-medium-benchmark-20261125.service', '--property=ActiveState', '--value')
raise 'Measurements active' unless status.success? && state.strip == 'inactive'
choice = JSON.parse(File.read(File.join(evaluation, 'default-visible-set-selection.json')))
raise 'Unresolved visibility choice' unless choice.fetch('publication_discussion_resolved') && choice.fetch('selected_visible_count') == 30
partial_paths = %w[summary.json aggregate/export.json aggregate/aggregate_results.csv validation/records.jsonl benchmark/benchmark_full_results.yaml benchmark/benchmark_results.yaml]
partial = partial_paths.to_h { |name| [name, sha.call(File.join(batch, name))] }
destination = File.join(batch, 'validation/spmv-work-count')
raise 'SpMV already exported' if File.exist?(destination)
checks = %w[test_native_spmv_export.rb test_gpt62_generation_evidence.rb test_fable51_supplement.rb test_batch_audit_selection.rb test_codex_usage_records.rb].map do |name|
  output, success = Open3.capture2e(RbConfig.ruby, File.join(root, 'tools', name), chdir: root)
  puts output
  raise "Regression failed: #{name}" unless success.success?
  { 'test' => name, 'passed' => true, 'output' => output }
end
evidence = File.join(evaluation, 'spmv-review')
pilot_quality = File.join(evidence, 'pilot-quality/quality-gate.json')
full_quality = File.join(evidence, 'full-quality/quality-gate.json')
[pilot_quality, full_quality].each { |path| raise 'Quality gate not passed' unless JSON.parse(File.read(path)).fetch('passed') }
supplemental = %w[pilot-quality full-quality].flat_map do |directory|
  Dir[File.join(evidence, directory, '*.json')].sort.map { |path| ["quality-evidence/#{directory}/#{File.basename(path)}", path] }
end.to_h
amendment = {
  'checked_at' => Time.now.utc.iso8601, 'passed' => true,
  'reason' => 'Resume evidence export after a legacy default location did not match the checked native SpMV pilot quality-gate location. No scientific records or decisions changed.',
  'original_gate_sha256' => sha.call(gate_path),
  'original_spmv_exporter_sha256' => sha.call(baseline_helper),
  'updated_spmv_exporter_sha256' => sha.call(changed_helper),
  'resume_driver_sha256' => sha.call(__FILE__), 'tests' => checks,
  'completed_partial_export_sha256' => partial,
  'quality_evidence_sha256' => supplemental.transform_values { |path| sha.call(path) },
  'repeated_validation_or_benchmark_runs' => 0
}
amendment_path = File.join(evaluation, 'release-export-resume-check.json')
raise 'Resume amendment already exists' if File.exist?(amendment_path)
File.write(amendment_path, JSON.pretty_generate(amendment) + "\n")
spmv = NativeSpmvExport.run(method_root: File.join(runtime, 'observer-pipeline-v5'),
  workspace: '/tmp/gpt62-medium-spmv-review-20261125-829313-s2ppjr', evidence: evidence,
  destination: destination, pilot_quality: pilot_quality, supplemental: supplemental)
raise 'Native SpMV scope differs' unless spmv.fetch('population') == 40 && spmv.fetch('remaining').zero? && spmv.fetch('new_failures').empty?
partial.each { |name, digest| raise "Completed export changed: #{name}" unless sha.call(File.join(batch, name)) == digest }
summary_path = File.join(batch, 'summary.json')
summary = JSON.parse(File.read(summary_path))
summary['native_spmv_review'] = { 'population' => spmv.fetch('population'), 'new_failures' => spmv.fetch('new_failures'),
  'export' => 'validation/spmv-work-count/export.json', 'export_sha256' => sha.call(File.join(destination, 'export.json')) }
File.write(summary_path, JSON.pretty_generate(summary) + "\n")
Gpt62Supplement.run(root: root, home: '/home/petert', phase: 'complete')
receipt = { 'exported_at' => Time.now.utc.iso8601, 'batch' => batch_id, 'records' => 440,
  'benchmarks' => 439, 'successful' => 439, 'corrections' => 24, 'release_workspace' => root,
  'completion_report_sha256' => sha.call(benchmark_path), 'resume_check_sha256' => sha.call(amendment_path),
  'driver_sha256' => sha.call(__FILE__), 'supplement_sha256' => sha.call(File.join(root, 'tools/export_gpt62_supplement.rb')),
  'generation_evidence_helper_sha256' => sha.call(File.join(root, 'tools/gpt62_generation_evidence.rb')),
  'scope' => 'Compact export complete; observer continuation provenance, combined scoring, winner reviews, package/site verification and publication remain required.' }
File.write(File.join(evaluation, 'batch-export.json'), JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, evaluation)
%w[release-export-resume-check.json resume-completed-batch-export.rb batch-export.json].each do |name|
  FileUtils.cp(File.join(evaluation, name), File.join(batch, 'completion', name))
end
puts JSON.pretty_generate(receipt)
