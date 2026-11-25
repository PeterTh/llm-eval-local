# frozen_string_literal: true
require 'json'
require 'digest'
require 'open3'
require 'time'
require 'fileutils'
require_relative 'artifact/tools/gpt62_generation_evidence'

runtime = __dir__
root = File.join(runtime, 'artifact')
campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium'
evaluation = File.join(campaign, 'evaluation')
destination = File.join(evaluation, 'release-export-check.json')
raise 'Export check already exists' if File.exist?(destination)
completion = JSON.parse(File.read(File.join(evaluation, 'benchmark-completion-review.json')))
raise 'Benchmark not complete' unless completion.fetch('verification') == 'passed' && completion.fetch('completed') == 439
state, success = Open3.capture2('systemctl', '--user', 'show', 'llm-gpt62-medium-benchmark-20261125.service', '--property=ActiveState', '--value')
raise 'Native measurements still active' unless success.success? && state.strip == 'inactive'
tests = %w[test_gpt62_generation_evidence.rb test_fable51_supplement.rb test_batch_audit_selection.rb
  test_codex_usage_records.rb test_native_spmv_export.rb]
checks = []
log_path = File.join(evaluation, 'release-export-tests.log')
File.open(log_path, 'wb') do |log|
  tests.each do |name|
    output, status = Open3.capture2e(RbConfig.ruby, File.join(root, 'tools', name), chdir: root)
    log.puts("TEST #{name}\n#{output}")
    checks << { 'test' => name, 'exit_status' => status.exitstatus, 'passed' => status.success? }
    raise "Export regression failed: #{name}\n#{output}" unless status.success?
  end
end
usage_path = File.join(campaign, 'codex-usage.jsonl')
usage = CodexUsageRecords.load_records(usage_path)
observations = Dir[File.join(campaign, 'observations/*.json')].sort.map { |path| JSON.parse(File.read(path)) }
requests_path = File.join(campaign, 'pricing/codex-request-usage.jsonl')
audit_path = File.join(campaign, 'pricing/request-context-audit.json')
reference_path = File.join(campaign, 'pricing/pricing-reference.json')
audit = JSON.parse(File.read(audit_path))
reference = JSON.parse(File.read(reference_path))
raise 'Request evidence changed' unless audit.fetch('final_usage_sha256') == Gpt62GenerationEvidence.sha(usage_path) &&
  audit.fetch('request_usage_sha256') == Gpt62GenerationEvidence.sha(requests_path)
request_check = Gpt62GenerationEvidence.verify_requests!(LocalEvalArtifact.read_jsonl(requests_path), usage, observations, audit, reference)
helpers = %w[tools/export_gpt62_supplement.rb tools/gpt62_generation_evidence.rb tools/test_gpt62_generation_evidence.rb
  tools/import_batch_aggregate.rb tools/export_native_spmv.rb].map { |path| File.join(root, path) } +
  %w[export-completed-batch.rb benchmark-export.rb benchmark-orchestration.rb].map { |name| File.join(runtime, name) }
report = { 'checked_at' => Time.now.utc.iso8601, 'passed' => true, 'tests' => checks,
  'native_request_counter_and_standard_cost_check' => request_check,
  'helper_sha256' => helpers.to_h { |path| [path, Gpt62GenerationEvidence.sha(path)] },
  'input_sha256' => [usage_path, requests_path, audit_path, reference_path, log_path,
    File.join(evaluation, 'benchmark-completion-review.json')].to_h { |path| [path, Gpt62GenerationEvidence.sha(path)] },
  'script_sha256' => Gpt62GenerationEvidence.sha(__FILE__),
  'scope' => 'Post-benchmark exporter regressions and compact native counter reconciliation only; no session reread, program run, performance rerun or model invocation.' }
File.write(destination, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, evaluation)
FileUtils.cp(File.join(runtime, 'test-winner-review-context.rb'), evaluation)
puts JSON.pretty_generate(report.slice('checked_at', 'passed', 'tests', 'native_request_counter_and_standard_cost_check'))
