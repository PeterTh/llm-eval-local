#!/usr/bin/env ruby
# frozen_string_literal: true
# Temporary causal ablations only: no writes to source Git or benchmark evidence.
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
raise 'Output exists' if File.exist?(options.fetch('output'))
require File.join(options.fetch('pipeline'), 'lib/local_evaluation/support')
pids, status = Open3.capture2('pgrep', '-u', 'llmtest')
raise 'Generation account active' unless status.exitstatus == 1 && pids.empty?
lock = LocalEvaluation::HostPerformanceLock.new
workspace = Dir.mktmpdir('gpt62-outlier-probe-', '/tmp')
runner = LocalEvaluation::ProcessRunner.new
context = JSON.parse(File.read(options.fetch('context')))
report = { 'schema_version' => 1, 'started_at' => Time.now.utc.iso8601,
  'purpose' => 'Limited outlier explanation. Diagnostic times are not benchmark samples and do not affect scores.',
  'workspace' => workspace, 'pipeline_commit' => LocalEvaluation.capture(['git', '-C', options.fetch('pipeline'), 'rev-parse', 'HEAD']).strip,
  'driver_sha256' => Digest::SHA256.file(__FILE__).hexdigest,
  'context_sha256' => Digest::SHA256.file(options.fetch('context')).hexdigest, 'experiments' => [] }
cases = [
  { id: 'black-scholes_gpt-6.2-sol-medium_mpi_r5', benchmark: 'black-scholes', backend: 'mpi', file: 'black_scholes.cpp', binary: 'black_scholes', n: 10_000_000, validation_n: 1031,
    toggle: 'GPT62_PROBE_DISABLE_CACHE', intervention: 'Recompute CDF coefficients for every option; retain fixed template setup, indexing, arithmetic, output handling and MPI timing.',
    edits: [
      ["using PricingTable = std::array<PricingParameters, testOptions.size()>;", "using PricingTable = std::array<PricingParameters, testOptions.size()>;\nconst bool probeDisableCache = std::getenv(\"GPT62_PROBE_DISABLE_CACHE\") != nullptr;"],
      ['    if (normal.ratio != ratio) {', '    if (probeDisableCache || normal.ratio != ratio) {']
    ] },
  { id: 'floydwarshall_gpt-6.2-sol-medium_omp_r3', benchmark: 'floydwarshall', backend: 'omp', file: 'floydwarshall.cpp', binary: 'floydwarshall', n: 8704, validation_n: 257,
    toggle: 'GPT62_PROBE_DISABLE_PRUNING', intervention: 'Keep every pivot candidate; retain blocking, saved pivot inputs, paired SIMD updates, path ties and timing.',
    edits: [
      ['    constexpr size_t tileSize = 64;  // One candidate bit per pivot.', "    const bool probeDisablePruning = std::getenv(\"GPT62_PROBE_DISABLE_PRUNING\") != nullptr;\n    constexpr size_t tileSize = 64;  // One candidate bit per pivot."],
      ['                            const bool possible = toPivots[pivot] + lowerBounds[pivot] < upperBound;',
       '                            const bool possible = probeDisablePruning || toPivots[pivot] + lowerBounds[pivot] < upperBound;']
    ] }
]
begin
  cases.each do |config|
    pin = context.fetch('source_pins').fetch(config.fetch(:id))
    stage = File.join(workspace, config.fetch(:id))
    pin.fetch('files').each do |relative, digest|
      source = File.join(options.fetch('sources'), pin.fetch('path'), relative)
      raise "Source pin differs: #{relative}" unless Digest::SHA256.file(source).hexdigest == digest
      destination = File.join(stage, relative)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(source, destination)
    end
    relative = File.join(config.fetch(:benchmark), config.fetch(:file))
    source = File.join(stage, relative)
    original = File.read(source)
    patch = "*** Begin Patch\n*** Update File: #{relative}\n"
    config.fetch(:edits).each do |from, to|
      raise 'Source anchor differs' unless original.scan(from).size == 1
      patch += "@@\n" + from.lines.map { |line| '-' + line.chomp + "\n" }.join + to.lines.map { |line| '+' + line.chomp + "\n" }.join
    end
    patch += "*** End Patch\n"
    output, success = Open3.capture2e('apply_patch', stdin_data: patch, chdir: stage)
    raise "Temporary ablation patch failed: #{output}" unless success.success?
    entry = { 'id' => config.fetch(:id), 'source_pin' => pin, 'patch' => patch,
      'modified_source_sha256' => Digest::SHA256.file(source).hexdigest,
      'intervention' => config.fetch(:intervention), 'runs' => [], 'checks' => [] }
    ok, error = LocalEvaluation::BuildSupport.build(source_dir: File.join(stage, config.fetch(:benchmark)),
      build_dir: File.join(stage, 'build'), runner: runner, par_type: config.fetch(:backend))
    raise error unless ok
    executable = File.join(stage, 'build', config.fetch(:binary))
    entry['executable_sha256'] = Digest::SHA256.file(executable).hexdigest
    results = []
    %w[normal disabled].each do |variant|
      env, argv = LocalEvaluation::Resources.new.command(par_type: config.fetch(:backend), executable: executable,
        args: ['-n', config.fetch(:validation_n).to_s, '-r', '-v'], mode: :validation)
      env[config.fetch(:toggle)] = '1' if variant == 'disabled'
      prefix = File.join(stage, "check-#{variant}")
      result = runner.run(argv: argv, env: env, prefix: prefix, timeout: 60, chdir: stage, limits: LocalEvaluation::ExecutionLimits::PERFORMANCE)
      stdout = File.read("#{prefix}_stdout.log")
      stderr = File.read("#{prefix}_stderr.log")
      raise "Diagnostic correctness check failed: #{stderr}" unless result.success
      block = stdout[/=== RESULTS ===.*?=== END RESULTS ===/m]
      raise 'Missing results block' unless block
      results << block
      entry['checks'] << { 'variant' => variant, 'argv' => argv, 'environment' => env, 'stdout' => stdout, 'stderr' => stderr }
    end
    raise 'Ablation changes observed results' unless results.uniq.size == 1
    entry['identical_check_results'] = true
    4.times do |sample|
      variants = sample.odd? ? %w[disabled normal] : %w[normal disabled]
      variants.each do |variant|
        env, argv = LocalEvaluation::Resources.new.command(par_type: config.fetch(:backend), executable: executable,
          args: ['-n', config.fetch(:n).to_s], mode: :benchmark)
        env[config.fetch(:toggle)] = '1' if variant == 'disabled'
        prefix = File.join(stage, "#{sample}-#{variant}")
        result = runner.run(argv: argv, env: env, prefix: prefix, timeout: 90, chdir: stage, limits: LocalEvaluation::ExecutionLimits::PERFORMANCE)
        stdout = File.read("#{prefix}_stdout.log")
        stderr = File.read("#{prefix}_stderr.log")
        raise "Probe failed: #{stderr}" unless result.success
        time = Float(stdout.match(/Computation time: ([\d.]+) ms/)[1])
        entry['runs'] << { 'sample' => sample.zero? ? 'warmup' : sample, 'variant' => variant, 'argv' => argv,
          'environment' => env, 'time_ms' => time, 'stdout' => stdout, 'stderr' => stderr }
        puts "#{config.fetch(:id)} #{variant} #{sample}: #{time} ms"
        $stdout.flush
      end
    end
    entry['median_ms'] = %w[normal disabled].to_h do |variant|
      times = entry.fetch('runs').select { |row| row['variant'] == variant && row['sample'] != 'warmup' }.map { |row| row.fetch('time_ms') }.sort
      [variant, times.fetch(1)]
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
