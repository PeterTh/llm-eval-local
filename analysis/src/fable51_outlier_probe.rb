#!/usr/bin/env ruby
# frozen_string_literal: true
# Diagnostic interventions only. Never updates benchmark records or source Git.
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'
require 'optparse'
require 'open3'
require 'time'
options = {}
OptionParser.new do |parser|
  %w[pipeline sources context output].each do |name|
    parser.on("--#{name}=PATH") { |path| options[name] = File.expand_path(path) }
  end
end.parse!
%w[pipeline sources context output].each { |name| options.fetch(name) }
raise 'Output already exists' if File.exist?(options.fetch('output'))
require File.join(options.fetch('pipeline'), 'lib/local_evaluation/support')
pids, status = Open3.capture2('pgrep', '-u', 'llmtest')
raise 'Generation account active' unless status.exitstatus == 1 && pids.empty?
lock = LocalEvaluation::HostPerformanceLock.new
workspace = Dir.mktmpdir('fable51-outlier-probe-', '/tmp')
runner = LocalEvaluation::ProcessRunner.new
context = JSON.parse(File.read(options.fetch('context')))
report = { 'schema_version' => 1, 'started_at' => Time.now.utc.iso8601,
  'purpose' => 'Limited outlier explanation; diagnostic times are not benchmark samples and do not affect scores',
  'workspace' => workspace, 'pipeline_commit' => LocalEvaluation.capture(['git', '-C', options.fetch('pipeline'), 'rev-parse', 'HEAD']).strip,
  'driver_sha256' => Digest::SHA256.file(__FILE__).hexdigest, 'experiments' => [] }
def replace_once(text, from, to)
  raise 'Source anchor differs' unless text.scan(from).size == 1
  text.sub(from, to)
end
begin
  [['cholesky', 'hybrid', 4096], ['qtclustering', 'omp', 6200]].each do |benchmark, backend, n|
    id = "#{benchmark}_claude-fable-5.1-cc-medium_#{backend}_r4"
    pin = context.fetch('source_pins').fetch(id)
    stage = File.join(workspace, id)
    pin.fetch('files').each do |relative, digest|
      source = File.join(options.fetch('sources'), pin.fetch('path'), relative)
      raise "Source pin differs: #{relative}" unless Digest::SHA256.file(source).hexdigest == digest
      destination = File.join(stage, relative)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(source, destination)
    end
    source = File.join(stage, benchmark, "#{benchmark}.cpp")
    original = File.read(source)
    modified = if benchmark == 'cholesky'
      value = replace_once(original, '    // Collect the full factor on rank 0 (needed for result printing / validation)',
        "    auto probe_collect_start = std::chrono::high_resolution_clock::now();\n    // Collect the full factor on rank 0 (needed for result printing / validation)")
      value = replace_once(value, '    if (printResults || validate) {', '    if (true) { // Diagnostic: collect the completed factor even without output flags')
      replace_once(value, '    // Print results for external validation', <<~CPP.chomp)
          MPI_CHECK(MPI_Barrier(MPI_COMM_WORLD));
          auto probe_collect_end = std::chrono::high_resolution_clock::now();
          if (root) printf("PROBE collection_ms: %.6f\\n", std::chrono::duration<double, std::milli>(probe_collect_end - probe_collect_start).count());
          // Print results for external validation
      CPP
    else
      value = replace_once(original, '    std::atomic<int> bound{0};',
        "    const bool probe_disable_pruning = std::getenv(\"FABLE_QT_DISABLE_PRUNING\") != nullptr;\n    std::atomic<int> bound{0};")
      replace_once(value, '            if (item.potential < cur_bound) return;',
        '            if (!probe_disable_pruning && item.potential < cur_bound) return;')
    end
    File.write(source, modified)
    entry = { 'id' => id, 'source_pin' => pin, 'modified_source_sha256' => Digest::SHA256.hexdigest(modified),
      'intervention' => benchmark == 'cholesky' ? 'Measure forced host collection after the unchanged decomposition interval' : 'Toggle only cardinality-upper-bound pruning; retain exact memberships, grid, SIMD and scheduling',
      'runs' => [] }
    ok, error = LocalEvaluation::BuildSupport.build(source_dir: File.join(stage, benchmark),
      build_dir: File.join(stage, 'build'), runner: runner, par_type: backend)
    raise error unless ok
    executable = File.join(stage, 'build', benchmark)
    entry['executable_sha256'] = Digest::SHA256.file(executable).hexdigest
    variants = benchmark == 'cholesky' ? ['collection'] : %w[normal no-pruning]
    4.times do |sample|
      variants.each do |variant|
        env, argv = LocalEvaluation::Resources.new.command(par_type: backend, executable: executable, args: ['-n', n.to_s], mode: :benchmark)
        env['FABLE_QT_DISABLE_PRUNING'] = '1' if variant == 'no-pruning'
        prefix = File.join(stage, "#{sample}-#{variant}")
        result = runner.run(argv: argv, env: env, prefix: prefix, timeout: 90, chdir: stage, limits: LocalEvaluation::ExecutionLimits::PERFORMANCE)
        stdout = File.read("#{prefix}_stdout.log")
        stderr = File.read("#{prefix}_stderr.log")
        raise "Probe failed: #{id} #{variant}: #{stderr}" unless result.success
        entry['runs'] << { 'sample' => sample.zero? ? 'warmup' : sample, 'variant' => variant,
          'argv' => argv, 'environment' => env, 'success' => result.success, 'stdout' => stdout, 'stderr' => stderr,
          'time_ms' => Float(stdout.match(/(?:Computation|Clustering) time: ([\d.]+) ms/)[1]),
          'collection_ms' => stdout[/PROBE collection_ms: ([\d.]+)/, 1]&.to_f }
        puts "#{id} #{variant} #{sample}: #{entry['runs'].last.slice('time_ms', 'collection_ms')}"
        $stdout.flush
      end
    end
    report['experiments'] << entry
    File.write(options.fetch('output'), JSON.pretty_generate(report) + "\n")
  end
  report['completed_at'] = Time.now.utc.iso8601
  report['successful'] = true
  File.write(options.fetch('output'), JSON.pretty_generate(report) + "\n")
ensure
  lock.close
end
