# frozen_string_literal: true
require 'json'
require 'digest'
require 'time'

commit = ARGV.fetch(0)
raise 'Invalid commit' unless commit.match?(/\A[0-9a-f]{40}\z/)
source = File.join(__dir__, 'resume-observer-rebuild-validation.rb')
before = File.read(source)
mapping = {
  "original = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation'" => "original = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3'",
  "successor = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3'" => "successor = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v4'",
  "old_pipeline = File.join(scratch, 'experiment')" => "old_pipeline = File.join(scratch, 'observer-pipeline-v3')",
  "new_pipeline = File.join(scratch, 'observer-pipeline-v3')" => "new_pipeline = File.join(scratch, 'observer-pipeline-v4')",
  "File.join(campaign, 'observer-rebuild-resume')" => "File.join(campaign, 'observer-helper-resume')",
  "old_check.fetch('ids').size == 26 && old_check.fetch('passed') == 26" => "old_check.fetch('ids').size == 32 && old_check.fetch('passed') == 32",
  "expected = %w[tools/validation_audit/full_array_adapters.rb tools/validation_audit/full_array_capture.rb tools/validation_audit/full_array_observer.py tools/validation_audit/native_full_array_validation.rb]" => "expected = %w[tools/validation_audit/full_array_adapters.rb tools/validation_audit/full_array_observer.py tools/validation_audit/native_full_array_validation.rb]",
  '3d2298fdbf94863d2de1acd9493a8f479a38ed03' => commit,
  'pilot-rebuilt-hybrid-options.rb' => 'pilot-result-helper-coverage.rb',
  'rebuilt-hybrid-options-pilot/pilot.json' => 'result-helper-coverage-pilot/pilot.json',
  "pilot.dig('result', 'passed')" => "pilot.fetch('observations').size == 9 && pilot.fetch('observations').all? { |row| row.dig('result', 'passed') }",
  'observer-identity-regression-tests.log' => 'observer-helper-host-regression-tests.log',
  '530 runs, 3171 assertions' => '532 runs, 3207 assertions',
  'observer-rebuild-resume-template.json' => 'observer-helper-resume-template.json',
  "FileUtils.cp_r(File.join(scratch, 'rebuilt-hybrid-options-pilot/full-array'), File.join(evidence, 'pilot-full-array'))" => "FileUtils.cp_r(File.join(scratch, 'result-helper-coverage-pilot'), File.join(evidence, 'pilot'))",
  "'pending_records' => 414" => "'pending_records' => 408",
  ".gsub(File.join(scratch, 'observer-pipeline'), new_pipeline).gsub(original + '-observer-v2', successor)" => '.gsub(old_pipeline, new_pipeline).gsub(original, successor)'
}
mapping.each_key { |key| raise "Missing template token: #{key}" unless before.include?(key) }
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
after = before.gsub(pattern) { |key| mapping.fetch(key) }
target = File.join(__dir__, 'resume-observer-helper-validation.rb')
raise 'Helper resume exists' if File.exist?(target)
File.write(target, after)
raise 'Syntax error' unless system('ruby', '-c', target)
receipt = { 'prepared_at' => Time.now.utc.iso8601, 'template' => source,
  'template_sha256' => Digest::SHA256.hexdigest(before), 'adapted_sha256' => Digest::SHA256.hexdigest(after),
  'mapping' => mapping, 'changes' => 'Import the 32 completed original validations without scientific changes; continue only pending records with reviewed additional helper coverage. Retain all initial attempts and nine read-only observer pilots.' }
File.write(File.join(__dir__, 'observer-helper-resume-template.json'), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt.except('mapping'))
