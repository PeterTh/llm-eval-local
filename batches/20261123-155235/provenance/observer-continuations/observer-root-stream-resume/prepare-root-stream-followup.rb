# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'time'

campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
evidence = File.join(campaign, 'observer-root-stream-resume')
config = JSON.parse(File.read(File.join(campaign, 'campaign.json')))
raise 'Wrong frozen pipeline' unless config.fetch('pipeline_commit') == '83e4f9f5bf4c1cfd6603269dcb580411744cf1dd'
raise 'Resume is not ready' unless File.file?(File.join(evidence, 'resume.json'))
receipt_path = File.join(evidence, 'followup-rebinding.json')
raise 'Follow-up rebinding exists' if File.exist?(receipt_path)
raise 'Review already started' if File.exist?(File.join(campaign, 'audit-pilot-launch.json'))
mapping = {
  File.join(__dir__, 'observer-pipeline-v4') => File.join(__dir__, 'observer-pipeline-v5'),
  '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v4' => config.fetch('validation_run'),
  '8a2488cd27ffc7a79f30dca1d77fe0a356ee64fd' => config.fetch('pipeline_commit'),
  '2e0cbb823d055ad6960384c7e5bb30d41f1b609e15ca562117d39e8a8485394b' => config.fetch('pipeline_source_sha256'),
  '"observer-pipeline-v4/tools/' => '"observer-pipeline-v5/tools/',
  "'observer-pipeline-v4/tools/" => "'observer-pipeline-v5/tools/",
  'File.join(scratch, "observer-pipeline-v4")' => 'File.join(scratch, "observer-pipeline-v5")',
  '532 passing regression tests' => '536 passing regression tests'
}
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
names = %w[audit-pilot-driver.rb audit-full-driver-policy.rb verify-primary-pilot.rb prepare-review-policy.rb launch-audit-pilot.rb launch-audit-full.rb timing-platform-context.txt prepare-spmv-review.rb verify-audit-completion.rb]
records = names.to_h do |name|
  path = File.join(__dir__, name)
  before = File.read(path)
  after = before.gsub(pattern) { |key| mapping.fetch(key) }
  if name == 'timing-platform-context.txt'
    after += "\nThree further exact-binary root-side streamed outputs are observed as their\noriginal reporting routines consume complete blocks. All three full-array pilots\npassed existing tolerances. No program or scientific acceptance rule changed.\nAll 114 completed validations, including one ordinary build failure, were retained.\n"
  end
  FileUtils.cp(path, File.join(evidence, 'pre-rebind-' + name))
  File.write(path, after)
  raise "Syntax error: #{name}" if name.end_with?('.rb') && !system('ruby', '-c', path)
  [name, { 'before_sha256' => Digest::SHA256.hexdigest(before), 'after_sha256' => Digest::SHA256.hexdigest(after) }]
end
launch_before = File.read(File.join(__dir__, 'launch-observer-helper-resume.rb'))
launch_after = launch_before.gsub("'observer-helper-resume'", "'observer-root-stream-resume'")
  .gsub('observer-pipeline-v4', 'observer-pipeline-v5')
  .gsub('408 pending', '326 pending').gsub("'reused_validations' => 32", "'reused_validations' => 114")
  .gsub("'pending_validations' => 408", "'pending_validations' => 326")
launch_path = File.join(__dir__, 'launch-observer-root-stream-resume.rb')
raise 'Root-stream launcher exists' if File.exist?(launch_path)
File.write(launch_path, launch_after)
raise 'Launcher syntax error' unless system('ruby', '-c', launch_path)
FileUtils.cp(__FILE__, evidence)
FileUtils.cp(File.join(__dir__, 'prepare-observer-root-stream-resume.rb'), evidence)
File.write(receipt_path, JSON.pretty_generate({ 'recorded_at' => Time.now.utc.iso8601,
  'mapping' => mapping, 'files' => records, 'launch_sha256' => Digest::SHA256.hexdigest(launch_after),
  'timing_review_started' => false, 'website_changed' => false }) + "\n")
puts 'Pending review helpers rebound; website hold unchanged.'
