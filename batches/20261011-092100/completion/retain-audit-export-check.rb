# frozen_string_literal: true
require 'digest'
require 'json'
require 'open3'
require 'fileutils'
require 'time'

evaluation = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
receipt = File.join(evaluation, 'audit-export-smoke.json')
raise 'Export smoke receipt already exists' if File.exist?(receipt)
checks = {
  'fable-export-regressions' => File.join(__dir__, 'artifact/tools/test_fable51_supplement.rb'),
  'audit-export-smoke' => File.join(__dir__, 'test-audit-export-smoke.rb'),
  'benchmark-eta-regressions' => File.join(__dir__, 'test-benchmark-eta.rb')
}.map do |name, path|
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, path)
  log = File.join(evaluation, name + '.log')
  raise "Check log already exists: #{log}" if File.exist?(log)
  File.write(log, stdout + stderr)
  raise "Check failed: #{name}" unless status.success?
  { 'name' => name, 'success' => true, 'exit_status' => status.exitstatus,
    'script_sha256' => Digest::SHA256.file(path).hexdigest,
    'log' => log, 'log_sha256' => Digest::SHA256.file(log).hexdigest }
end
files = [File.join(__dir__, 'artifact/tools/export_fable51_supplement.rb'),
  File.join(__dir__, 'artifact/tools/test_fable51_supplement.rb'),
  File.join(__dir__, 'test-audit-export-smoke.rb'), __FILE__]
retained = files.to_h do |source|
  destination = File.join(evaluation, File.basename(source))
  if File.file?(destination) && File.binread(destination) != File.binread(source)
    backup = destination.sub(/\.rb\z/, '-before-diagnostic-retention.rb')
    raise 'Preparation backup already exists' if File.exist?(backup)
    FileUtils.cp(destination, backup)
  end
  FileUtils.cp(source, destination)
  [File.basename(source), Digest::SHA256.file(source).hexdigest]
end
report = { 'checked_at' => Time.now.utc.iso8601, 'passed' => true, 'checks' => checks,
  'retained_helpers' => retained,
  'amendment' => 'Preserve native-export schema-failure diagnostics only when the complete underlying attempt metadata is unchanged. The real audit smoke test verifies all 14 rejected-attempt diagnostics, platform reconciliation, original review preservation, all 283 responses, and the 120-program resolved selection.',
  'program_executions' => 0, 'actual_batch_exported' => false, 'published' => false }
File.write(receipt, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
