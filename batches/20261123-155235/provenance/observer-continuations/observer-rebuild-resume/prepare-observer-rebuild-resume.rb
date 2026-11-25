# frozen_string_literal: true
require 'json'
require 'digest'
require 'time'

scratch = __dir__
source = File.join(scratch, 'resume-observer-validation.rb')
before = File.read(source)
mapping = {
  "successor = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v2'" => "successor = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3'",
  "new_pipeline = File.join(scratch, 'observer-pipeline')" => "new_pipeline = File.join(scratch, 'observer-pipeline-v3')",
  "File.join(campaign, 'observer-resume')" => "File.join(campaign, 'observer-rebuild-resume')",
  '585774790137b750c1b15fafec5af81cef6e1463' => '3d2298fdbf94863d2de1acd9493a8f479a38ed03',
  'pilot-streamed-hybrid-options.rb' => 'pilot-rebuilt-hybrid-options.rb',
  'streamed-hybrid-options-pilot/' => 'rebuilt-hybrid-options-pilot/',
  'observer-regression-tests.log' => 'observer-identity-regression-tests.log',
  '528 runs, 3106 assertions' => '530 runs, 3171 assertions',
  'observer-resume-template.json' => 'observer-rebuild-resume-template.json',
  "config['observer_resume_history'] = [File.join(evidence, 'resume.json')]" => "config['observer_resume_history'] = Array(config['observer_resume_history']) + [File.join(evidence, 'resume.json')]",
  '.gsub(old_pipeline, new_pipeline).gsub(original, successor)' => ".gsub(File.join(scratch, 'observer-pipeline'), new_pipeline).gsub(original + '-observer-v2', successor)"
}
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
after = before.gsub(pattern) { |key| mapping.fetch(key) }
target = File.join(scratch, 'resume-observer-rebuild-validation.rb')
raise 'Rebuild resume helper exists' if File.exist?(target)
File.write(target, after)
raise 'Syntax error' unless system('ruby', '-c', target)
receipt = { 'prepared_at' => Time.now.utc.iso8601, 'template' => source,
  'template_sha256' => Digest::SHA256.hexdigest(before), 'adapted_sha256' => Digest::SHA256.hexdigest(after),
  'mapping' => mapping, 'changes' => 'Import the same 26 original completed records into a new immutable manifest with strict nvcc-symbol-PID-tolerant observer identity. Retain both stopped runs and both targeted observer pilots. No source, numerical criterion or performance-setting changes.' }
File.write(File.join(scratch, 'observer-rebuild-resume-template.json'), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt.except('mapping'))
