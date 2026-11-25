# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'time'

campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
evidence = File.join(campaign, 'observer-helper-resume')
config = JSON.parse(File.read(File.join(campaign, 'campaign.json')))
raise 'Wrong frozen pipeline' unless config.fetch('pipeline_commit') == '8a2488cd27ffc7a79f30dca1d77fe0a356ee64fd'
raise 'Resume is not ready' unless File.file?(File.join(evidence, 'resume.json'))
receipt_path = File.join(evidence, 'followup-rebinding.json')
raise 'Follow-up rebinding exists' if File.exist?(receipt_path)
raise 'Review already started' if File.exist?(File.join(campaign, 'audit-pilot-launch.json'))
mapping = {
  File.join(__dir__, 'observer-pipeline-v3') => File.join(__dir__, 'observer-pipeline-v4'),
  '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3' => config.fetch('validation_run'),
  '3d2298fdbf94863d2de1acd9493a8f479a38ed03' => config.fetch('pipeline_commit'),
  '9f6d1a09ee23231a9a84b53a63359d9d24e903e9daac7b81ade83b8d75614a54' => config.fetch('pipeline_source_sha256'),
  '"observer-pipeline-v3/tools/' => '"observer-pipeline-v4/tools/',
  "'observer-pipeline-v3/tools/" => "'observer-pipeline-v4/tools/",
  'File.join(scratch, "observer-pipeline-v3")' => 'File.join(scratch, "observer-pipeline-v4")',
  '530 passing regression tests' => '532 passing regression tests'
}
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
names = %w[audit-pilot-driver.rb audit-full-driver-policy.rb verify-primary-pilot.rb prepare-review-policy.rb launch-audit-pilot.rb launch-audit-full.rb timing-platform-context.txt prepare-spmv-review.rb verify-audit-completion.rb]
records = names.to_h do |name|
  path = File.join(__dir__, name)
  before = File.read(path)
  after = before.gsub(pattern) { |key| mapping.fetch(key) }
  if name == 'timing-platform-context.txt'
    after += "\nReviewed pointer/span helpers and two exact ELF-pinned MPI streaming sites\nare now observable without source or executable changes. A nine-program pilot\nmatched all complete arrays exactly. Original criteria and resource profiles\nare unchanged; previously completed validation receipts are retained.\n"
  end
  FileUtils.cp(path, File.join(evidence, 'pre-rebind-' + name))
  File.write(path, after)
  raise "Syntax error: #{name}" if name.end_with?('.rb') && !system('ruby', '-c', path)
  [name, { 'before_sha256' => Digest::SHA256.hexdigest(before), 'after_sha256' => Digest::SHA256.hexdigest(after) }]
end
launch_before = File.read(File.join(__dir__, 'launch-observer-rebuild-resume.rb'))
launch_after = launch_before.gsub("'observer-rebuild-resume'", "'observer-helper-resume'")
  .gsub('observer-pipeline-v3', 'observer-pipeline-v4')
  .gsub('414 pending', '408 pending').gsub("'reused_validations' => 26", "'reused_validations' => 32")
  .gsub("'pending_validations' => 414", "'pending_validations' => 408")
launch_path = File.join(__dir__, 'launch-observer-helper-resume.rb')
raise 'Helper launcher exists' if File.exist?(launch_path)
File.write(launch_path, launch_after)
raise 'Launcher syntax error' unless system('ruby', '-c', launch_path)
FileUtils.cp(__FILE__, evidence)
FileUtils.cp(File.join(__dir__, 'prepare-observer-helper-resume.rb'), evidence)
File.write(receipt_path, JSON.pretty_generate({ 'recorded_at' => Time.now.utc.iso8601,
  'mapping' => mapping, 'files' => records, 'launch_sha256' => Digest::SHA256.hexdigest(launch_after),
  'timing_review_started' => false, 'website_changed' => false }) + "\n")
puts 'Pending review helpers rebound; website hold unchanged.'
