# frozen_string_literal: true
require 'open3'
require 'tmpdir'
require 'time'
require_relative 'artifact/tools/export_timing_revision_evidence'

campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
receipt = File.join(campaign, 'correction-history-export-check.json')
raise 'Correction history export check already retained' if File.exist?(receipt)
helper = File.join(__dir__, 'artifact/tools/export_timing_revision_evidence.rb')
test = File.join(__dir__, 'artifact/tools/test_timing_revision_evidence.rb')
output, status = Open3.capture2e('ruby', test)
raise "Correction history tests failed: #{output}" unless status.success?
log = File.join(campaign, 'correction-history-export-tests.log')
File.write(log, output)
temporary = Dir.mktmpdir('fable51-revision-export-smoke-', '/tmp')
report = TimingRevisionEvidenceExport.run(batch_dir: temporary, gate_path: File.join(campaign, 'correction-revision-1.json'))
files = LocalEvalArtifact.regular_files(temporary)
raise 'Unexpected binary/source/transcript retention' if files.any? { |path| path.match?(/\.(?:o|a|so|cpp|cu|s|bin|exe)\z/) || File.basename(path) == 'events.jsonl' }
gate = JSON.parse(File.read(File.join(campaign, 'correction-revision-1.json')))
raise 'Wrong revision scope' unless gate.fetch('accepted_corrections') == 69 && gate.fetch('unchanged_proposals') == 68
[helper, test, __FILE__].each { |path| FileUtils.cp(path, campaign) }
record = {
  'checked_at' => Time.now.utc.iso8601, 'passed' => true, 'tests_exit_status' => status.exitstatus,
  'tests_log_sha256' => LocalEvalArtifact.sha256(log), 'export' => report,
  'exporter_sha256' => LocalEvalArtifact.sha256(helper), 'tests_sha256' => LocalEvalArtifact.sha256(test),
  'temporary_smoke_destination' => temporary, 'source_program_executions' => 0,
  'policy' => 'Real-evidence export smoke only, separate from the final release batch. Prior correction drafts and reviews remain traceable without full event streams, build artifacts or repeated unchanged response bodies.'
}
File.write(receipt, JSON.pretty_generate(record) + "\n")
puts JSON.pretty_generate(record.reject { |key, _| key == 'export' }.merge('files' => report.fetch('files'), 'bytes' => report.fetch('bytes')))
