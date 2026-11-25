# frozen_string_literal: true
require '/home/petert/llm_eval/experiment/tools/validation_audit/native_full_array_validation'

root = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation'
id = 'black-scholes_gpt-6.2-sol-medium_hybrid_r2'
actual = File.join(root, 'validation', id)
reference = File.join(root, 'validation/reference/black-scholes')
destination = File.join(__dir__, 'streamed-hybrid-options-pilot')
raise 'Pilot already exists' if File.exist?(destination)
raise 'Generation account active' if system('pgrep', '-u', 'llmtest', out: File::NULL)
state, = Open3.capture2('systemctl', '--user', 'show', 'llm-gpt62-medium-validation-20261125.service', '--property=ActiveState', '--value')
raise 'Validation still active' if %w[active activating reloading].include?(state.strip)
host_lock = LocalEvaluation::HostPerformanceLock.new
session = ValidationAudit::NativeFullArray::Session.new
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
begin
  result = session.check(id: id, benchmark: 'black-scholes', backend: 'hybrid',
    executable: File.join(actual, 'black_scholes'), source_root: File.join(actual, 'source'),
    reference_executable: File.join(reference, 'black_scholes'), reference_source_root: File.join(reference, 'source'),
    output_dir: destination)
  report = { 'checked_at' => Time.now.utc.iso8601, 'id' => id,
    'source_commit' => '7a0a8b8e28af48d4ee2525c13ced317726536b25',
    'binary_sha256' => ValidationAudit.sha(File.join(actual, 'black_scholes')),
    'elapsed_seconds' => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
    'result' => result, 'program_source_changes' => 0, 'executable_file_changes' => 0,
    'compilation' => 0, 'benchmark_runs' => 0, 'method_sha256' => ValidationAudit::NativeFullArray.methods }
  ValidationAudit.save(File.join(destination, 'pilot.json'), report)
  puts JSON.pretty_generate(report)
ensure
  session.close
  host_lock.close
end
