# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'time'

campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
evidence = File.join(campaign, 'observer-rebuild-resume')
raise 'Resume is not ready' unless File.file?(File.join(evidence, 'resume.json'))
receipt_path = File.join(evidence, 'followup-rebinding.json')
raise 'Follow-up rebinding exists' if File.exist?(receipt_path)
raise 'Review already started' if File.exist?(File.join(campaign, 'audit-pilot-launch.json'))
mapping = {
  File.join(__dir__, 'observer-pipeline') => File.join(__dir__, 'observer-pipeline-v3'),
  '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v2' => '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3',
  '585774790137b750c1b15fafec5af81cef6e1463' => '3d2298fdbf94863d2de1acd9493a8f479a38ed03',
  '38abff145af0cb04b9a740737aa2e829b6632d1d2d2f43559db01d9dc35fd691' => '9f6d1a09ee23231a9a84b53a63359d9d24e903e9daac7b81ade83b8d75614a54',
  '"observer-pipeline/tools/' => '"observer-pipeline-v3/tools/',
  "'observer-pipeline/tools/" => "'observer-pipeline-v3/tools/",
  'File.join(scratch, "observer-pipeline")' => 'File.join(scratch, "observer-pipeline-v3")',
  '528 passing regression tests' => '530 passing regression tests'
}
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
names = %w[audit-pilot-driver.rb audit-full-driver-policy.rb verify-primary-pilot.rb prepare-review-policy.rb launch-audit-pilot.rb launch-audit-full.rb timing-platform-context.txt prepare-spmv-review.rb verify-audit-completion.rb]
records = names.to_h do |name|
  path = File.join(__dir__, name)
  before = File.read(path)
  after = before.gsub(pattern) { |key| mapping.fetch(key) }
  if name == 'timing-platform-context.txt'
    after += "\nThe observer identity also permits only the inspected eight-hex-digit nvcc\ntemporary filename PID in non-loaded ELF symbol metadata. Every other binary\nbyte remains pinned; actual source/executable hashes are retained unchanged.\n"
  end
  FileUtils.cp(path, File.join(evidence, 'pre-rebind-' + name))
  File.write(path, after)
  raise "Syntax error: #{name}" if name.end_with?('.rb') && !system('ruby', '-c', path)
  [name, { 'before_sha256' => Digest::SHA256.hexdigest(before), 'after_sha256' => Digest::SHA256.hexdigest(after) }]
end
launch_before = File.read(File.join(__dir__, 'launch-observer-resume.rb'))
launch_after = launch_before.gsub("'observer-resume'", "'observer-rebuild-resume'")
  .gsub("'observer-pipeline/lib/", "'observer-pipeline-v3/lib/")
  .gsub("File.join(scratch, 'observer-pipeline')", "File.join(scratch, 'observer-pipeline-v3')")
launch_path = File.join(__dir__, 'launch-observer-rebuild-resume.rb')
raise 'Rebuild launcher exists' if File.exist?(launch_path)
File.write(launch_path, launch_after)
raise 'Launcher syntax error' unless system('ruby', '-c', launch_path)
FileUtils.cp(__FILE__, evidence)
FileUtils.cp(File.join(__dir__, 'prepare-observer-rebuild-resume.rb'), evidence)
File.write(receipt_path, JSON.pretty_generate({ 'recorded_at' => Time.now.utc.iso8601,
  'mapping' => mapping, 'files' => records, 'launch_sha256' => Digest::SHA256.hexdigest(launch_after),
  'timing_review_started' => false, 'website_changed' => false }) + "\n")
puts 'Pending static-review helpers and continuation launcher rebound; website hold unchanged.'
