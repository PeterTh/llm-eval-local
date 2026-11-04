require_relative 'probe'
root = __dir__
lock = LocalEvaluation::HostPerformanceLock.new
runner = LocalEvaluation::ProcessRunner.new
results = []
%w[floydwarshall stencil3d].each do |benchmark|
  directory = "#{root}/counterexamples/#{benchmark}"
  FileUtils.mkdir_p(directory)
  binary = "#{directory}/counterexample"
  command = ['/usr/bin/g++-13', '-std=c++20', '-O3', '-march=native']
  command << '-DFLOYD_PROBE' if benchmark == 'floydwarshall'
  command += ["#{root}/comparator_counterexample.cpp", '-o', binary]
  build = runner.run(argv: command, env: {}, prefix: "#{directory}/build", chdir: root,
    timeout: 30, limits: LocalEvaluation::ExecutionLimits::BUILD)
  raise 'compile failed' unless build.success
  outs = %w[reference deliberately_wrong].map do |variant|
    argv = variant == 'reference' ? [binary] : [binary, 'mutate']
    run = runner.run(argv: argv, env: {}, prefix: "#{directory}/#{variant}", chdir: root,
      timeout: 30, limits: LocalEvaluation::ExecutionLimits::VALIDATION)
    raise 'counterexample execution failed' unless run.success
    File.read("#{directory}/#{variant}_stdout.log")
  end
  comparison = validate(*outs, benchmark)
  result = { 'benchmark' => benchmark, 'kind' => 'deliberately_corrupted_reference_result_not_a_winner',
    'original_internal_validator_accepted' => outs.last.include?('Validation: PASSED'),
    'native_external_comparator_accepted' => comparison.first, 'comparison' => comparison,
    'numerical_corruption' => File.read("#{directory}/deliberately_wrong_stderr.log").strip,
    'input_program_changed' => false, 'winner_program_changed' => false }
  WinnerProbe.save("#{directory}/result.json", result)
  puts JSON.generate(result)
  results << result
end
directory = "#{root}/counterexamples/spmv_repetition"
binary = "#{root}/build/reference_spmv/spmv"
run = runner.run(argv: [binary, '-v', '-r', '-n', '1025', '-s', '40', '-i', '1'],
  env: { 'CUDA_VISIBLE_DEVICES' => '', 'OMP_NUM_THREADS' => '1' },
  prefix: "#{directory}/one_iteration", chdir: root, timeout: 30,
  limits: LocalEvaluation::ExecutionLimits::VALIDATION)
raise 'SpMV reference execution failed' unless run.success
one = File.read("#{directory}/one_iteration_stdout.log")
eleven = File.read("#{root}/probes/reference_spmv/run_stdout.log")
comparison = validate(eleven, one, 'spmv')
blocks = [one,eleven].map { |s| s.split('=== RESULTS ===')[1].split('=== END RESULTS ===')[0] }
result = { 'benchmark' => 'spmv', 'kind' => 'unchanged_reference_one_vs_eleven_repetitions',
  'native_external_comparator_accepted' => comparison.first, 'comparison' => comparison,
  'result_blocks_identical_including_hash' => blocks[0] == blocks[1],
  'both_internal_validators_accepted' => [one,eleven].all? { |s| s.include?('Validation: PASSED') },
  'no_claim_about_winner_omitting_iterations' => true }
WinnerProbe.save("#{directory}/result.json", result)
results << result
WinnerProbe.save("#{root}/counterexamples/results.json", results)
puts JSON.generate(result)
lock.close
