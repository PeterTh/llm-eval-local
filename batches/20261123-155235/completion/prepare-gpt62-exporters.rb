# frozen_string_literal: true
require 'digest'
require 'json'
require 'fileutils'
require 'time'

scratch = __dir__
evaluation = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
template = '/home/petert/llm-eval-local/tools/export_fable51_supplement.rb'
expected = '4c1306da6681ab8c1b2f0823676c9f873ce858986684b2da2492cdf60b6468eb'
raise 'Supplement template changed' unless Digest::SHA256.file(template).hexdigest == expected
destination = File.join(scratch, 'export_gpt62_supplement.rb')
receipt_path = File.join(evaluation, 'release-export-preparation.json')
raise 'Export preparation already exists' if File.exist?(destination) || File.exist?(receipt_path)
text = File.binread(template)
replacements = {
  "require_relative 'fable51_generation_evidence'" => "require_relative 'gpt62_generation_evidence'",
  'Fable51' => 'Gpt62',
  '# Native exporters own validation, timing patches and measurements. This adds\n# the reconciled timing selection and compact Claude generation provenance.' =>
    '# Native exporters own validation, timing patches and measurements. This adds\n# the reconciled timing selection and compact Codex generation provenance.',
  '#{BATCH}-fable51-medium' => '#{BATCH}-gpt62-astra-sol-medium',
  'llm_timing_audit/20261107-fable51-medium' => 'llm_timing_audit/20261125-gpt62-astra-sol-medium',
  'test-fable51-generation-evidence.rb' => 'test_gpt62_generation_evidence.rb',
  'Same-source all-backend QT decisions and any explicitly reconciled overlap overlay the general audit. All review evidence is retained.' =>
    'Same-source QT, user-approved fixed-size Black-Scholes setup policy, and targeted cross-review decisions overlay the general audit in the recorded order. Every earlier finding is retained.',
  "      summary = JSON.parse(File.read(File.join(batch, 'summary.json')))\n      summary['timing_audit_final_verdicts']" =>
    "      Gpt62GenerationEvidence.retain_policy_history!(evaluation: evaluation, audit: audit, copy: copy, jsonl: jsonl)\n      summary = JSON.parse(File.read(File.join(batch, 'summary.json')))\n      summary['timing_audit_final_verdicts']",
  "    puts 'Retained 220 Fable observations, exact accounting, retry history, amendments and pricing.'" =>
    "    puts 'Retained 440 Astra/Sol 6.2 observations, exact accounting, selected Standard pricing and compact request evidence.'"
}
changes = replacements.map do |before, after|
  # Convert only the documentary newline spelling in the comment replacement.
  before = before.gsub('\\n', "\n")
  after = after.gsub('\\n', "\n")
  count = text.scan(before).size
  raise "Missing template fragment: #{before}" if count.zero?
  text = text.gsub(before, after)
  { 'before' => before, 'after' => after, 'occurrences' => count }
end
raise 'Stale campaign identity' if text.include?('Fable51') || text.include?('20261107-fable51') || text.include?('#{BATCH}-fable51')
File.binwrite(destination, text)

source = File.join(scratch, 'observer-pipeline-v5/tools/timing_audit/bin/export_benchmark_batch.rb')
binding_destination = File.join(scratch, 'benchmark-export.rb')
raise 'Benchmark export binding already exists' if File.exist?(binding_destination)
binding_text = File.binread(source)
bindings = {
  'require_relative "benchmark_validation_batch"' => "require #{File.join(scratch, 'benchmark-orchestration').inspect}",
  'require_relative "export_timing_corrections"' => "require #{File.join(scratch, 'observer-pipeline-v5/tools/timing_audit/bin/export_timing_corrections').inspect}"
}
bindings.each do |before, after|
  raise 'Missing exporter dependency' unless binding_text.scan(before).size == 1
  binding_text = binding_text.sub(before, after)
end
File.binwrite(binding_destination, binding_text)
files = [__FILE__, destination, binding_destination,
  File.join(scratch, 'gpt62_generation_evidence.rb'), File.join(scratch, 'test_gpt62_generation_evidence.rb')]
files.each do |file|
  raise "Syntax failure: #{file}" unless system(RbConfig.ruby, '-c', file, out: File::NULL)
  FileUtils.cp(file, evaluation)
end
receipt = {
  'prepared_at' => Time.now.utc.iso8601, 'status' => 'prepared_not_executed_or_tested',
  'supplement_template' => template, 'supplement_template_sha256' => expected,
  'mechanical_substitutions' => changes, 'benchmark_export_source' => source,
  'benchmark_export_source_sha256' => Digest::SHA256.file(source).hexdigest,
  'benchmark_dependency_rebindings' => bindings,
  'orchestration_sha256' => Digest::SHA256.file(File.join(scratch, 'benchmark-orchestration.rb')).hexdigest,
  'prepared_files_sha256' => files.to_h { |file| [File.basename(file), Digest::SHA256.file(file).hexdigest] },
  'scope' => 'Text-only preparation. No artifact checkout, export, model call, build, benchmark or test suite execution. Full unit/integration verification required after measurements stop.'
}
File.write(receipt_path, JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt.slice('prepared_at', 'status', 'prepared_files_sha256', 'scope'))
