require 'json'
require 'digest'
require 'fileutils'
require 'open3'

# Evidence export only. No compiler, benchmark or model invocation.
workspace = File.realpath(ARGV.fetch(0))
destination = File.expand_path(ARGV.fetch(1))
raise 'Refusing to overwrite evidence' if File.exist?(destination)
def read_json(path) = JSON.parse(File.read(path))
def sha(path) = Digest::SHA256.file(path).hexdigest
def git(repo, *args)
  out, err, status = Open3.capture3('git', '-C', repo, *args)
  raise err unless status.success?
  out
end
def log_record(path, limit = nil)
  bytes = File.binread(path)
  truncated = limit && bytes.bytesize > limit
  kept = truncated ? bytes.byteslice(0, limit / 2) + "\n[bounded excerpt]\n" + bytes.byteslice(-limit / 2, limit / 2) : bytes
  { 'text' => kept.encode('UTF-8', invalid: :replace, undef: :replace),
    'bytes' => bytes.bytesize, 'sha256' => Digest::SHA256.hexdigest(bytes), 'truncated' => !!truncated }
end
inventory = read_json("#{workspace}/inventory.json")
manifest = read_json("#{workspace}/probe-manifest.json")
raise 'Inventory changed' unless sha("#{workspace}/inventory.json") == manifest.fetch('inventory_sha256')
coverage = read_json(File.join(__dir__, 'coverage.json'))
raise 'Incomplete review coverage' unless coverage.keys.sort == inventory.fetch('winners').map { |w| w.fetch('cell') }.sort

checks = %w[probes branch-probes mpi128-probes].flat_map do |phase|
  Dir["#{workspace}/#{phase}/*/result.json"].sort.map do |path|
    row = read_json(path)
    directory = File.dirname(path)
    command = File.read("#{directory}/run_command.log")
    error = File.read("#{directory}/run_stderr.log")
    outcome = if row.fetch('passed')
      row.fetch('id').start_with?('reference_') ? 'reference_pass' : 'winner_pass'
    else
      retry_path = "#{workspace}/mpi128-probes/#{File.basename(directory)}/result.json"
      raise "Unexpected failed check #{path}" unless phase == 'branch-probes' &&
        File.basename(directory).start_with?('mpi128_') && command.include?('TasksMax\\=256') &&
        error.match?(/system limit on number of children|pmix_progress_thread_start|pthread_create/) &&
        read_json(retry_path).fetch('passed')
      'diagnostic_launcher_limit_failure_superseded'
    end
    row.merge('check_id' => "#{phase}/#{File.basename(directory)}", 'outcome' => outcome,
      'raw_result_sha256' => sha(path),
      'command' => { 'raw_sha256' => sha("#{directory}/run_command.log"),
        'selected_lines' => command.lines.select { |line| line.match?(/^\s*(OMP_[A-Z_]+|CUDA_VISIBLE_DEVICES)=|^command:|^effective_command:/) }.join },
      'stdout' => log_record("#{directory}/run_stdout.log"),
      'stderr' => log_record("#{directory}/run_stderr.log", 3000))
  end
end

counterexamples = read_json("#{workspace}/counterexamples/results.json").map do |row|
  benchmark = row.fetch('benchmark')
  paths = if benchmark == 'spmv'
    ["#{workspace}/probes/reference_spmv/run", "#{workspace}/counterexamples/spmv_repetition/one_iteration"]
  else
    %w[reference deliberately_wrong].map { |variant| "#{workspace}/counterexamples/#{benchmark}/#{variant}" }
  end
  row.merge('outputs' => paths.map do |prefix|
    { 'stdout' => log_record("#{prefix}_stdout.log"), 'stderr' => log_record("#{prefix}_stderr.log"),
      'exit_code' => File.read("#{prefix}_exitcode.log").strip,
      'command_sha256' => sha("#{prefix}_command.log") }
  end)
end

experiment = '/home/petert/llm_eval/experiment'
method_paths = %w[validation_helper.rb lib/local_evaluation.rb lib/local_evaluation/support.rb lib/local_evaluation/external_validation_cases.rb lib/local_evaluation/validation_pipeline.rb]
method_pins = method_paths.to_h { |path| [path, sha("#{experiment}/#{path}")] }
source_base = 'https://github.com/PeterTh/llm-eval-generated/blob'
winners = inventory.fetch('winners').map do |row|
  main = row.fetch('files').keys.find { |path| path.end_with?('.cpp', '.cu') }
  selected = row.slice('cell', 'id', 'median_ms', 'args', 'timing_fixed', 'source_commit', 'source_path', 'files', 'validation_evidence')
  selected.merge('source_url' => "#{source_base}/#{row.fetch('source_commit')}/#{row.fetch('source_path')}/#{main}",
    'existing_review' => "analysis/notes/individual/#{row.fetch('id')}.md",
    'audit_observation' => coverage.fetch(row.fetch('cell')),
    'successful_checks' => checks.select { |c| c['id'] == row['id'] && c['outcome'] == 'winner_pass' }.map { |c| c.fetch('check_id') })
end
builds = manifest.fetch('rows').map do |row|
  { 'id' => row.fetch('id'), 'source_commit' => row.fetch('source_commit'), 'source_files' => row.fetch('files'), 'cache' => row.fetch('cache') }
end
evidence = {
  'schema' => 1, 'date' => '2026-11-03',
  'scope' => 'Diagnostic audit of all 44 current benchmark/backend winners; not a validation-policy or release-eligibility change.',
  'release_commit' => inventory.fetch('release_commit'), 'release_winners_sha256' => inventory.fetch('release_winners_sha256'),
  'input_commit' => inventory.fetch('input_commit'),
  'experiment_commit' => git(experiment, 'rev-parse', 'HEAD').strip,
  'method_sha256' => method_pins,
  'original_driver_sha256' => %w[inventory.rb probe.rb counterexamples.rb comparator_counterexample.cpp].to_h { |name| [name, sha("#{workspace}/#{name}")] },
  'input_helpers' => %w[hash.hpp results_output.hpp].to_h { |name| ["common/#{name}", sha("#{workspace}/reference/common/#{name}")] },
  'counts' => { 'winners' => winners.size, 'successful_winner_checks' => checks.count { |c| c['outcome'] == 'winner_pass' },
    'successful_reference_checks' => checks.count { |c| c['outcome'] == 'reference_pass' },
    'superseded_diagnostic_launch_failures' => checks.count { |c| c['outcome'] == 'diagnostic_launcher_limit_failure_superseded' },
    'counterexamples' => counterexamples.size },
  'changes_to_programs_or_release' => false, 'benchmark_samples_replaced' => 0,
  'cases' => manifest.fetch('cases'), 'winners' => winners, 'verified_builds' => builds,
  'checks' => checks, 'counterexamples' => counterexamples
}
FileUtils.mkdir_p(destination)
File.write("#{destination}/evidence.json", JSON.pretty_generate(evidence) + "\n")
File.write("#{destination}/evidence.sha256", "#{sha("#{destination}/evidence.json")}  evidence.json\n")
puts JSON.generate(evidence.fetch('counts').merge('evidence_bytes' => File.size("#{destination}/evidence.json")))
