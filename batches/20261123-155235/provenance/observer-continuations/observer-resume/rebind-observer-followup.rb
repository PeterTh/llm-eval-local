# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'time'

campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
evidence = File.join(campaign, 'observer-resume')
resume = JSON.parse(File.read(File.join(evidence, 'resume.json')))
raise 'Timing review already started' if File.exist?(File.join(campaign, 'audit-pilot-launch.json'))
destination = File.join(evidence, 'followup-rebinding.json')
raise 'Follow-up already rebound' if File.exist?(destination)
mapping = {
  File.join(__dir__, 'experiment') => File.join(__dir__, 'observer-pipeline'),
  resume.fetch('initial_run') => resume.fetch('successor_run'),
  '9bb3b950765df6d7c2f49c5c562a5c7478f7c7bc' => '585774790137b750c1b15fafec5af81cef6e1463',
  resume.fetch('initial_pipeline').fetch('sha256') => resume.fetch('successor_pipeline').fetch('sha256'),
  '"experiment/tools/' => '"observer-pipeline/tools/',
  "'experiment/tools/" => "'observer-pipeline/tools/",
  'File.join(scratch, "experiment")' => 'File.join(scratch, "observer-pipeline")'
}
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
names = %w[audit-pilot-driver.rb audit-full-driver-policy.rb verify-primary-pilot.rb prepare-review-policy.rb launch-audit-pilot.rb launch-audit-full.rb timing-platform-context.txt prepare-spmv-review.rb verify-audit-completion.rb]
records = names.to_h do |name|
  path = File.join(__dir__, name)
  before = File.read(path)
  FileUtils.cp(path, File.join(evidence, 'pre-rebind-' + name))
  after = before.gsub(pattern) { |key| mapping.fetch(key) }
  if name == 'timing-platform-context.txt'
    old = "same strengthening checks applied to the existing release. The launch gate\nverifies exact pipeline/toolchain/resource-profile agreement with the completed Fable\nobserver-v3 evaluation, including its read-only observer coverage fixes."
    replacement = "same strengthening checks applied to the existing release. The initial launch\ngate verified exact pipeline/toolchain/resource-profile agreement with the completed\nFable observer-v3 evaluation. The successor adds one binary-scoped read-only\nobserver adapter for streamed hybrid option output, with a checked native pilot,\n528 passing regression tests and explicit reuse of 26 completed validations.\nScientific comparisons, inputs, tolerances and resource profiles are unchanged."
    raise 'Platform context differs' unless after.include?(old)
    after = after.sub(old, replacement)
  end
  File.write(path, after)
  raise "Syntax error: #{name}" if name.end_with?('.rb') && !system('ruby', '-c', path)
  [name, { 'before_sha256' => Digest::SHA256.hexdigest(before), 'after_sha256' => Digest::SHA256.hexdigest(after) }]
end
FileUtils.cp(__FILE__, evidence)
FileUtils.cp(File.join(__dir__, 'prepare-observer-resume.rb'), evidence)
File.write(destination, JSON.pretty_generate({ 'recorded_at' => Time.now.utc.iso8601,
  'resume_sha256' => Digest::SHA256.file(File.join(evidence, 'resume.json')).hexdigest,
  'mapping' => mapping, 'files' => records, 'timing_review_started' => false,
  'policy' => 'Rebind prepared follow-up helpers to the clean additive observer pipeline and successor validation. No reviewer response or generated source exists to modify; all initial helper bytes are retained.' }) + "\n")
puts "Rebound #{records.size} pending follow-up helpers; no reviews launched."
