require 'json'
require 'digest'
require 'open3'
require 'fileutils'
require 'time'
require File.join(ENV.fetch('WINNER_AUDIT_EXPERIMENT', '/home/petert/llm_eval/experiment'), 'lib/local_evaluation')

module WinnerProbe
  extend self
  ROOT = __dir__
  raise 'Copy these scripts to a fresh local /tmp workspace first' unless File.realpath(ROOT).start_with?('/tmp/')
  CASES = {
    'black-scholes' => %w[-n 10003],
    'cahn-hilliard' => %w[-x 65 -y 61 -z 67 -i 21],
    'cholesky' => %w[-n 513],
    'floydwarshall' => %w[-n 513],
    'matmul' => %w[-n 513],
    'nbody' => %w[-n 1031 -s 11],
    'qtclustering' => %w[-n 1001 -t 1.3],
    'roomsim' => %w[-n 320 -t 101 -s 7 -r 0.7],
    'spmv' => %w[-n 1025 -s 40 -i 11],
    'stencil3d' => %w[-x 65 -y 61 -z 67 -i 21],
    'unstructured' => %w[-n 33 -i 513]
  }.freeze
  def sha(file) = Digest::SHA256.file(file).hexdigest
  def read(file) = JSON.parse(File.read(file))
  def save(file, data)
    raise "Already exists: #{file}" if File.exist?(file)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, JSON.pretty_generate(data) + "\n")
  end
  def tree_hashes(dir)
    Dir["#{dir}/**/*"].select { |p| File.file?(p) && !File.symlink?(p) }.sort.to_h { |p| [p.delete_prefix(dir + '/'), sha(p)] }
  end
  def prepare
    inv = read("#{ROOT}/inventory.json")
    rows = inv.fetch('winners').map do |w|
      benchmark, backend = w.fetch('cell').split('/')
      w.merge('benchmark' => benchmark, 'backend' => backend,
        'source_root' => "#{ROOT}/sources/#{w.fetch('id')}")
    end
    CASES.each_key do |benchmark|
      paths = Dir["#{ROOT}/reference/{#{benchmark},common}/**/*"].select { |p| File.file?(p) }
      rows << { 'id' => "reference_#{benchmark}", 'benchmark' => benchmark, 'backend' => 'sequential',
        'source_root' => "#{ROOT}/reference", 'source_commit' => inv.fetch('input_commit'),
        'files' => paths.to_h { |p| [p.delete_prefix("#{ROOT}/reference/"), { 'sha256' => sha(p) }] } }
    end
    rows.each do |row|
      name = row.fetch('benchmark').tr('-', '_')
      candidates = if row.fetch('backend') == 'sequential'
        Dir["/home/petert/llm_para_local_evaluation/*/validation/reference/#{row.fetch('benchmark')}"]
      else
        Dir["/home/petert/llm_para_local_evaluation/*/{validation,benchmark}/#{row.fetch('id')}"]
      end
      expected = row.fetch('files').transform_values { |v| v.fetch('sha256') }
      candidates.sort.reverse.each do |dir|
        binary = "#{dir}/#{name}"
        next unless File.executable?(binary) && File.file?(binary)
        next unless %w[build cmake].all? { |s| File.file?("#{dir}/#{s}_exitcode.log") && File.read("#{dir}/#{s}_exitcode.log").strip == '0' }
        next unless tree_hashes("#{dir}/source") == expected
        next unless File.mtime(binary) <= File.mtime("#{dir}/build_exitcode.log")
        row['cache'] = { 'executable' => binary, 'sha256' => sha(binary), 'build_directory' => dir,
          'receipts' => %w[cmake_command.log cmake_exitcode.log build_command.log build_exitcode.log source_staging.yaml].to_h { |f| [f, sha("#{dir}/#{f}")] } }
        break
      end
      puts "#{row.fetch('id')}: #{row['cache'] ? 'verified cache' : 'needs build'}"
    end
    save("#{ROOT}/probe-manifest.json", {
      'created_at' => Time.now.utc.iso8601, 'inventory_sha256' => sha("#{ROOT}/inventory.json"),
      'cases' => CASES, 'rows' => rows, 'policy' => 'Read-only scientific diagnostics: unchanged exact-source programs, unchanged comparator/tolerances, no published evidence or eligibility changes. Builds/execution local /tmp. One small nondefault shape per winner, not performance measurements.' })
  end
  def run
    manifest = read("#{ROOT}/probe-manifest.json")
    raise 'inventory changed' unless sha("#{ROOT}/inventory.json") == manifest.fetch('inventory_sha256')
    pids, _, s = Open3.capture3('pgrep', '-u', 'llmtest')
    raise 'generation active' unless s.exitstatus == 1 && pids.empty?
    lock = LocalEvaluation::HostPerformanceLock.new
    resources = LocalEvaluation::Resources.new
    resources.verify_topology!
    runner = LocalEvaluation::ProcessRunner.new
    rows = manifest.fetch('rows').sort_by { |r| [r.fetch('backend') == 'sequential' ? 0 : 1, r.fetch('id')] }
    rows.each do |row|
      id = row.fetch('id')
      destination = "#{ROOT}/probes/#{id}"
      if File.file?("#{destination}/result.json")
        puts "Retained existing diagnostic #{id}"
        next
      end
      build_dir = "#{ROOT}/build/#{id}"
      FileUtils.mkdir_p(build_dir)
      name = row.fetch('benchmark').tr('-', '_')
      if (cache = row['cache'])
        raise 'binary changed' unless sha(cache.fetch('executable')) == cache.fetch('sha256')
        cache.fetch('receipts').each { |f,d| raise 'receipt changed' unless sha("#{cache.fetch('build_directory')}/#{f}") == d }
        binary = "#{build_dir}/#{name}"
        FileUtils.cp(cache.fetch('executable'), binary, preserve: true)
      else
        source = LocalEvaluation::BuildSupport.stage_source(source_root: row.fetch('source_root'), benchmark: row.fetch('benchmark'), stage_root: "#{build_dir}/source")
        ok, error = LocalEvaluation::BuildSupport.build(source_dir: source, build_dir: build_dir, runner: runner, par_type: row.fetch('backend'))
        raise "build failed #{id}: #{error}" unless ok
        binary = LocalEvaluation::BuildSupport.find_executable(build_dir, row.fetch('benchmark'))
      end
      args = %w[-v -r] + manifest.fetch('cases').fetch(row.fetch('benchmark'))
      # Roomsim uses -r VALUE for reflectivity; the result-output flag is -o.
      args = %w[-v -o] + manifest.fetch('cases').fetch('roomsim') if row.fetch('benchmark') == 'roomsim'
      env, command = row.fetch('backend') == 'sequential' ?
        [{ 'CUDA_VISIBLE_DEVICES' => '', 'OMP_NUM_THREADS' => '1' }, [binary, *args]] :
        resources.command(par_type: row.fetch('backend'), executable: binary, args: args, mode: :validation)
      run = runner.run(argv: command, env: env, prefix: "#{destination}/run", chdir: build_dir,
        timeout: 30, limits: LocalEvaluation::ExecutionLimits::VALIDATION)
      output = File.read("#{destination}/run_stdout.log")
      internal = output.include?('Validation: PASSED') && !output.include?('Validation: FAILED') && !output.include?('Validation fail')
      comparison = if row.fetch('backend') != 'sequential' && run.success
        ref = "#{ROOT}/probes/reference_#{row.fetch('benchmark')}"
        raise 'reference unsuccessful' unless read("#{ref}/result.json").fetch('passed')
        validate(File.read("#{ref}/run_stdout.log"), output, row.fetch('benchmark'))
      end
      result = { 'id' => id, 'arguments' => args, 'execution' => run.to_h,
        'internal_validation' => internal, 'comparison' => comparison, 'binary_sha256' => sha(binary),
        'passed' => run.success && internal && (comparison.nil? || comparison.first),
        'source_commit' => row.fetch('source_commit'), 'checked_at' => Time.now.utc.iso8601 }
      save("#{destination}/result.json", result)
      puts JSON.generate(result.slice('id', 'passed', 'internal_validation', 'comparison').merge('wall_seconds' => run.wall_seconds))
      $stdout.flush
      raise 'reference failed' if row.fetch('backend') == 'sequential' && !result.fetch('passed')
    end
  ensure
    lock&.close
  end
  def branch(mpi128_retry = false)
    manifest = read("#{ROOT}/probe-manifest.json")
    rows = manifest.fetch('rows').to_h { |r| [r.fetch('id'), r] }
    cases = rows.values.select { |r| r['backend'] == 'mpi' }.map do |r|
      { 'name' => "mpi128_#{r['id']}", 'id' => r['id'], 'args' => CASES.fetch(r['benchmark']),
        'reference' => "#{ROOT}/probes/reference_#{r['benchmark']}", 'mode' => :benchmark,
        'purpose' => 'Correctness with the actual 128-rank measurement topology, not a performance measurement' }
    end
    extra_cases = [
      ['cahn-hilliard_claude-opus-5-cc-medium_omp_r4', %w[-x 512 -i 3], 'fused512'],
      ['stencil3d_claude-opus-5-cc-medium_omp_r1', %w[-x 512 -i 3], 'streaming512'],
      ['cholesky_claude-opus-5.5-cc-medium_omp_r1', %w[-n 1537], 'block96'],
      ['spmv_gpt-6.1-sol-xhigh_hybrid_r4', %w[-n 1024 -s 10 -i 67], 'graph64plus3']
    ]
    extra_cases = [] if mpi128_retry
    extra_cases.each do |id,args,label|
      b = rows.fetch(id).fetch('benchmark')
      reference_name = "reference_#{label}"
      cases << { 'name' => reference_name, 'id' => "reference_#{b}", 'args' => args, 'mode' => :validation,
        'purpose' => 'Unchanged sequential reference for fast-path diagnostic' }
      cases << { 'name' => "#{label}_#{id}", 'id' => id, 'args' => args,
        'reference' => "#{ROOT}/branch-probes/#{reference_name}", 'mode' => :benchmark,
        'purpose' => 'Exercise measured-size fast path or graph-tail logic omitted by small validation' }
    end
    base = mpi128_retry ? 'mpi128-probes' : 'branch-probes'
    save("#{ROOT}/#{mpi128_retry ? 'mpi128-plan' : 'branch-plan'}.json", cases)
    pids, _, s = Open3.capture3('pgrep', '-u', 'llmtest')
    raise 'generation active' unless s.exitstatus == 1 && pids.empty?
    lock = LocalEvaluation::HostPerformanceLock.new
    resources = LocalEvaluation::Resources.new
    runner = LocalEvaluation::ProcessRunner.new
    cases.each do |c|
      row = rows.fetch(c.fetch('id'))
      dir = "#{ROOT}/#{base}/#{c.fetch('name')}"
      binary = "#{ROOT}/build/#{row.fetch('id')}/#{row.fetch('benchmark').tr('-', '_')}"
      expected_binary = read("#{ROOT}/probes/#{row.fetch('id')}/result.json").fetch('binary_sha256')
      raise 'binary changed' unless sha(binary) == expected_binary
      args = (row.fetch('benchmark') == 'roomsim' ? %w[-v -o] : %w[-v -r]) + c.fetch('args')
      env, command = row.fetch('backend') == 'sequential' ?
        [{ 'CUDA_VISIBLE_DEVICES' => '', 'OMP_NUM_THREADS' => '1' }, [binary, *args]] :
        resources.command(par_type: row.fetch('backend'), executable: binary, args: args, mode: c.fetch('mode'))
      limits = c.fetch('mode') == :benchmark ? LocalEvaluation::ExecutionLimits::PERFORMANCE : LocalEvaluation::ExecutionLimits::VALIDATION
      run = runner.run(argv: command, env: env, prefix: "#{dir}/run", chdir: File.dirname(binary),
        timeout: 30, limits: limits)
      output = File.read("#{dir}/run_stdout.log")
      internal = output.include?('Validation: PASSED') && !output.include?('Validation: FAILED') && !output.include?('Validation fail')
      comparison = if c['reference'] && run.success
        raise 'reference unsuccessful' unless read("#{c['reference']}/result.json").fetch('passed')
        validate(File.read("#{c['reference']}/run_stdout.log"), output, row.fetch('benchmark'))
      end
      result = c.merge('arguments' => args, 'execution' => run.to_h, 'internal_validation' => internal,
        'comparison' => comparison, 'passed' => run.success && internal && (comparison.nil? || comparison.first),
        'checked_at' => Time.now.utc.iso8601, 'source_commit' => row.fetch('source_commit'), 'binary_sha256' => sha(binary))
      save("#{dir}/result.json", result)
      puts JSON.generate(result.slice('name','id','passed','comparison').merge('wall_seconds' => run.wall_seconds))
      $stdout.flush
      raise 'reference failed' if !c['reference'] && !result.fetch('passed')
    end
  ensure
    lock&.close
  end
  def mpi128_retry = branch(true)
end
WinnerProbe.public_send(ARGV.fetch(0)) if $PROGRAM_NAME == __FILE__
