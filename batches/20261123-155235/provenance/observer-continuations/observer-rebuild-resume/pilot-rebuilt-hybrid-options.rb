# frozen_string_literal: true
require '/home/petert/llm_eval/experiment/tools/validation_audit/native_full_array_validation'

original = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation'
root = original + '-observer-v2'
id = 'black-scholes_gpt-6.2-sol-medium_hybrid_r2'
actual = File.join(root, 'validation', id)
reference = File.join(root, 'validation/reference/black-scholes')
destination = File.join(__dir__, 'rebuilt-hybrid-options-pilot')
raise 'Pilot already exists' if File.exist?(destination)
raise 'Generation account active' if system('pgrep', '-u', 'llmtest', out: File::NULL)
state, = Open3.capture2('systemctl', '--user', 'show', 'llm-gpt62-medium-validation-20261125.service', '--property=ActiveState', '--value')
raise 'Validation still active' if %w[active activating reloading].include?(state.strip)
before = File.binread(File.join(original, 'validation', id, 'black_scholes'))
after = File.binread(File.join(actual, 'black_scholes'))
raise 'Binary lengths differ' unless before.bytesize == after.bytesize
differences = (0...before.bytesize).select { |index| before.getbyte(index) != after.getbyte(index) }
raise 'Unreviewed executable difference' unless !differences.empty? && differences.all? { |index| (849618...849626).cover?(index) }
identity = ValidationAudit::FullArrayAdapters::NVCC_TEMPFILE_IDENTITIES.values.first
raise 'Reviewed images differ outside the temporary symbol PID' unless [before, after].all? { |bytes|
  ValidationAudit::FullArrayAdapters.normalized_nvcc_pid_digest(bytes, identity) == identity.fetch('normalized_sha256') }
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
    'original_binary_sha256' => Digest::SHA256.hexdigest(before), 'rebuilt_binary_sha256' => Digest::SHA256.hexdigest(after),
    'different_byte_offsets' => differences, 'normalized_identity' => identity,
    'all_other_bytes_identical' => true, 'elapsed_seconds' => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
    'result' => result, 'program_source_changes' => 0, 'executable_file_changes' => 0,
    'compilation' => 0, 'benchmark_runs' => 0, 'method_sha256' => ValidationAudit::NativeFullArray.methods }
  ValidationAudit.save(File.join(destination, 'pilot.json'), report)
  puts JSON.pretty_generate(report)
ensure
  session.close
  host_lock.close
end
