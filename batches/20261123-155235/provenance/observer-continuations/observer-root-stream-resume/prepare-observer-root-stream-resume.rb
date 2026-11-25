# frozen_string_literal: true
require 'json'
require 'digest'
require 'time'

commit = ARGV.fetch(0)
raise 'Invalid commit' unless commit.match?(/\A[0-9a-f]{40}\z/)
source = File.join(__dir__, 'resume-observer-helper-validation.rb')
before = File.read(source)
mapping = {
  "original = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3'" => "original = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v4'",
  "successor = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v4'" => "successor = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v5'",
  "old_pipeline = File.join(scratch, 'observer-pipeline-v3')" => "old_pipeline = File.join(scratch, 'observer-pipeline-v4')",
  "new_pipeline = File.join(scratch, 'observer-pipeline-v4')" => "new_pipeline = File.join(scratch, 'observer-pipeline-v5')",
  "File.join(campaign, 'observer-helper-resume')" => "File.join(campaign, 'observer-root-stream-resume')",
  "old_check.fetch('ids').size == 32 && old_check.fetch('passed') == 32" => "old_check.fetch('ids').size == 114 && old_check.fetch('passed') == 113",
  "expected = %w[tools/validation_audit/full_array_adapters.rb tools/validation_audit/full_array_observer.py tools/validation_audit/native_full_array_validation.rb]" => "expected = %w[tools/validation_audit/full_array_adapters.rb tools/validation_audit/full_array_capture.rb tools/validation_audit/native_full_array_validation.rb]",
  '8a2488cd27ffc7a79f30dca1d77fe0a356ee64fd' => commit,
  'pilot-result-helper-coverage.rb' => 'pilot-root-stream-coverage.rb',
  'result-helper-coverage-pilot' => 'root-stream-coverage-pilot',
  "pilot.fetch('observations').size == 9" => "pilot.fetch('observations').size == 3",
  'observer-helper-host-regression-tests.log' => 'observer-root-stream-host-regression-tests.log',
  '532 runs, 3207 assertions' => '536 runs, 3265 assertions',
  'observer-helper-resume-template.json' => 'observer-root-stream-resume-template.json',
  "'pending_records' => 408" => "'pending_records' => 326"
}
mapping.each_key { |key| raise "Missing template token: #{key}" unless before.include?(key) }
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
after = before.gsub(pattern) { |key| mapping.fetch(key) }
target = File.join(__dir__, 'resume-observer-root-stream-validation.rb')
raise 'Root stream resume exists' if File.exist?(target)
File.write(target, after)
raise 'Syntax error' unless system('ruby', '-c', target)
receipt = { 'prepared_at' => Time.now.utc.iso8601, 'template' => source,
  'template_sha256' => Digest::SHA256.hexdigest(before), 'adapted_sha256' => Digest::SHA256.hexdigest(after),
  'mapping' => mapping, 'changes' => 'Retain 113 passes and one ordinary CMake build failure without retries or scientific changes; continue only the 326 pending records with reviewed root-stream observers. Retain all initial attempts and three successful read-only pilots.' }
File.write(File.join(__dir__, 'observer-root-stream-resume-template.json'), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt.except('mapping'))
