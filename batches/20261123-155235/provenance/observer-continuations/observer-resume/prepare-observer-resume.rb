# frozen_string_literal: true
require 'json'
require 'digest'
require 'time'

template = '/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra/evaluation/stencil-observer-resume/resume-stencil-observer-validation.rb'
before = File.read(template)
mapping = {
  '/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra/evaluation' => '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation',
  '/home/petert/llm_para_local_evaluation/20261106-terra61-ultra-codex-validation-observer-v2' => '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation',
  '/home/petert/llm_para_local_evaluation/20261106-terra61-ultra-codex-validation-observer-v3' => '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v2',
  "old_pipeline = File.join(scratch, 'observer-pipeline')" => "old_pipeline = File.join(scratch, 'experiment')",
  "new_pipeline = File.join(scratch, 'observer-pipeline-v3')" => "new_pipeline = File.join(scratch, 'observer-pipeline')",
  "File.join(campaign, 'stencil-observer-resume')" => "File.join(campaign, 'observer-resume')",
  'llm-terra61-ultra-codex-validation-20261106.service' => 'llm-gpt62-medium-validation-20261125.service',
  "old_check.fetch('ids').size == 193 && old_check.fetch('passed') == 192" => "old_check.fetch('ids').size == 26 && old_check.fetch('passed') == 26",
  'tools/validation_audit/full_array_capture.rb tools/validation_audit/native_full_array_validation.rb' => 'tools/validation_audit/full_array_capture.rb tools/validation_audit/full_array_observer.py tools/validation_audit/native_full_array_validation.rb',
  '592706fe997a184b21ed3a4044d1a9896b131a1d' => '585774790137b750c1b15fafec5af81cef6e1463',
  'pilot-streamed-stencil.rb' => 'pilot-streamed-hybrid-options.rb',
  'streamed-stencil-pilot/full-array' => 'streamed-hybrid-options-pilot/full-array',
  "'pending_records' => 27" => "'pending_records' => 414",
  "[config.fetch('observer_resume_evidence'), File.join(evidence, 'resume.json')]" => "[File.join(evidence, 'resume.json')]",
  'verify-validation-completion.rb evaluation-status.rb' => 'verify-validation-completion.rb'
}
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
after = before.gsub(pattern) { |key| mapping.fetch(key) }
insertion = "  FileUtils.cp(File.join(scratch, 'pilot-streamed-hybrid-options.rb'), evidence)\n"
raise 'Pilot retention point differs' unless after.scan(insertion).size == 1
after = after.sub(insertion, insertion + <<~'RUBY'.lines.map { |line| '  ' + line }.join)
  pilot_path = File.join(scratch, 'streamed-hybrid-options-pilot/pilot.json')
  pilot = JSON.parse(File.read(pilot_path))
  raise 'Pilot did not pass with the frozen method' unless pilot.dig('result', 'passed') &&
    pilot.fetch('method_sha256') == ValidationAudit::NativeFullArray.methods
  FileUtils.cp(pilot_path, evidence)
  tests = File.read(File.join(scratch, 'observer-regression-tests.log'))
  raise 'Regression gate missing' unless tests.include?('528 runs, 3106 assertions, 0 failures, 0 errors, 0 skips')
  FileUtils.cp(File.join(scratch, 'observer-regression-tests.log'), evidence)
  FileUtils.cp(File.join(scratch, 'observer-resume-template.json'), evidence)
RUBY
target = File.join(__dir__, 'resume-observer-validation.rb')
raise 'Resume helper exists' if File.exist?(target)
File.write(target, after)
raise 'Resume helper syntax error' unless system('ruby', '-c', target)
receipt = { 'prepared_at' => Time.now.utc.iso8601, 'template' => template,
  'template_sha256' => Digest::SHA256.hexdigest(before), 'adapted_sha256' => Digest::SHA256.hexdigest(after),
  'mapping' => mapping, 'changes' => 'Campaign identities, 26 reusable records, 414 pending records, the four additive observer-method files, and exact successful pilot/regression bindings. Original evidence is retained; scientific acceptance criteria and benchmark settings do not change.' }
File.write(File.join(__dir__, 'observer-resume-template.json'), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt.except('mapping'))
