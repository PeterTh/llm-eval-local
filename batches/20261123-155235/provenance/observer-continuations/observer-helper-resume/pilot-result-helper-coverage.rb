# frozen_string_literal: true
require '/home/petert/llm_eval/experiment/tools/validation_audit/native_full_array_validation'
$stdout.sync = true

root = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3'
campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
inventory = JSON.parse(File.read(File.join(campaign, 'helper-compatibility-preflight/inventory.json')))
raise 'Unexpected helper inventory' unless inventory.size == 9 && inventory.map { |row| row.fetch('helper_sha256') }.uniq.size == 7
destination = File.join(__dir__, 'result-helper-coverage-pilot')
raise 'Pilot already exists' if File.exist?(destination)
raise 'Generation account active' if system('pgrep', '-u', 'llmtest', out: File::NULL)
%w[llm-gpt62-medium-validation-20261125.service llm-gpt62-helper-coverage-20261125.service].each do |unit|
  state, = Open3.capture2('systemctl', '--user', 'show', unit, '--property=ActiveState', '--value')
  raise 'Validation still active' if %w[active activating reloading].include?(state.strip)
end
host_lock = LocalEvaluation::HostPerformanceLock.new
session = ValidationAudit::NativeFullArray::Session.new
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
observations = []
begin
  inventory.each do |row|
    id = row.fetch('id')
    benchmark, _, backend, = id.split('_')
    actual = File.join(root, 'validation', id)
    reference = File.join(root, 'validation/reference', benchmark)
    executable = LocalEvaluation.executable_name(benchmark)
    raise 'Helper changed' unless ValidationAudit.sha(File.join(actual, 'source/common/results_output.hpp')) == row.fetch('helper_sha256')
    observed_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = session.check(id: id, benchmark: benchmark, backend: backend,
      executable: File.join(actual, executable), source_root: File.join(actual, 'source'),
      reference_executable: File.join(reference, executable), reference_source_root: File.join(reference, 'source'),
      output_dir: File.join(destination, id))
    observations << row.merge('binary_sha256' => ValidationAudit.sha(File.join(actual, executable)),
      'elapsed_seconds' => Process.clock_gettime(Process::CLOCK_MONOTONIC) - observed_at, 'result' => result)
    puts JSON.generate(observations.last)
  end
  report = { 'checked_at' => Time.now.utc.iso8601, 'observations' => observations,
    'source_commit' => '7a0a8b8e28af48d4ee2525c13ced317726536b25',
    'elapsed_seconds' => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
    'program_source_changes' => 0, 'executable_file_changes' => 0, 'compilation' => 0, 'benchmark_runs' => 0,
    'method_sha256' => ValidationAudit::NativeFullArray.methods }
  ValidationAudit.save(File.join(destination, 'pilot.json'), report)
  puts JSON.pretty_generate(report.slice('checked_at', 'elapsed_seconds').merge(
    'passed' => observations.count { |row| row.dig('result', 'passed') }, 'total' => observations.size))
ensure
  session.close
  host_lock.close
end
