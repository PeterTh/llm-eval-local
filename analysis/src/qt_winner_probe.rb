#!/usr/bin/env ruby
# frozen_string_literal: true
# Focused correctness evidence only: never changes benchmark records or scores.
require "optparse"
require "json"
require "digest"
require "fileutils"
require "tmpdir"
options = {}
OptionParser.new do |p|
  %w[pipeline native-run corrected-run reference output workspace].each do |key|
    p.on("--#{key}=PATH") { |value| options[key] = File.expand_path(value) }
  end
end.parse!
%w[pipeline native-run corrected-run reference output workspace].each { |key| raise "missing --#{key}" unless options[key] }
require File.join(options.fetch("pipeline"), "lib/local_evaluation/support")
workspace = options.fetch("workspace")
raise "workspace must be below /tmp" unless workspace.start_with?("/tmp/")
FileUtils.mkdir_p(workspace)
runner = LocalEvaluation::ProcessRunner.new
lock = LocalEvaluation::HostPerformanceLock.new
begin
  reference = File.join(workspace, "qt-reference")
  source = File.join(options.fetch("reference"), "qtclustering/qtclustering.cpp")
  compiled = runner.run(argv: [LocalEvaluation::CXX_COMPILER, "-std=c++20", "-O3", "-march=native", source, "-o", reference],
                        prefix: File.join(workspace, "compile"), timeout: 60, limits: LocalEvaluation::ExecutionLimits::BUILD)
  raise "reference build failed" unless compiled.success
  output = options.fetch("output")
  preliminary = File.file?(output) ? JSON.parse(File.read(output)).fetch("preliminary_attempts", JSON.parse(File.read(output)).fetch("results", [])) : []
  report = { "schema_version" => 2, "purpose" => "correctness-only; probe timings are not benchmark data",
             "method" => "Unchanged sequential reference at N=1200; cross-implementation agreement of four independently generated winners at every inherited benchmark N. Agreement is supporting evidence, not a proof or a replacement reference.",
             "preliminary_attempts" => preliminary, "comparisons" => [] }
  [1200, 4000, 5000, 6200, 7800].each do |n|
    comparison = { "n" => n, "oracle" => n == 1200 ? "sequential reference" : "cross-implementation agreement", "runs" => [] }
    suffixes = %w[mpi_r5 hybrid_r1 omp_r2 cuda_r5]
    suffixes.unshift("reference") if n == 1200
    suffixes.each do |suffix|
    backend = suffix.split("_").first
    id = "qtclustering_claude-opus-5-cc-medium_#{suffix}"
    native = %w[mpi hybrid].include?(backend) ? options.fetch("corrected-run") : options.fetch("native-run")
    original_executable = suffix == "reference" ? reference : File.join(native, "validation", id, "qtclustering")
    executable = suffix == "reference" ? reference : File.join(workspace, id)
    FileUtils.cp(original_executable, executable) unless suffix == "reference"
    entry = { "id" => id, "n" => n, "reference_source_sha256" => Digest::SHA256.file(source).hexdigest,
              "executable_sha256" => Digest::SHA256.file(executable).hexdigest, "runs" => {} }
    [[suffix == "reference" ? "reference" : "candidate", executable]].each do |kind, binary|
      args = ["-n", n.to_s, "-v", "-r"]
      env, argv = if kind == "reference"
                    [{ "CUDA_VISIBLE_DEVICES" => "", "OMP_NUM_THREADS" => "1" }, ["numactl", "--physcpubind=0", "--membind=0", binary, *args]]
                  else
                    LocalEvaluation::Resources.new.command(par_type: backend, executable: binary, args: args, mode: :benchmark)
                  end
      prefix = File.join(workspace, "#{id}-#{n}-#{kind}")
      result = runner.run(argv: argv, env: env, prefix: prefix, timeout: 240, chdir: workspace,
                          limits: LocalEvaluation::ExecutionLimits::PERFORMANCE)
      stdout = File.read("#{prefix}_stdout.log")
      stderr = File.read("#{prefix}_stderr.log")
      entry["runs"][kind] = { "success" => result.success, "timed_out" => result.timed_out,
                              "argv" => argv, "environment" => env, "stdout" => stdout, "stderr" => stderr,
                              "result_block" => stdout[/=== RESULTS ===.*?=== END RESULTS ===/m] }
      puts "#{id} N=#{n} #{kind}: #{result.success ? 'completed' : 'FAILED'}"
      $stdout.flush
    end
    comparison["runs"] << entry
    end
    runs = comparison.fetch("runs").flat_map { |entry| entry.fetch("runs").values }
    comparison["all_completed"] = runs.all? { |run| run["success"] && run["result_block"] }
    comparison["exact_result_block_match"] = comparison["all_completed"] ? runs.map { |run| run["result_block"] }.uniq.size == 1 : nil
    report["comparisons"] << comparison
    File.write(output, JSON.pretty_generate(report) + "\n")
    raise "QT correctness probe inconclusive or mismatching at N=#{n}" unless comparison["exact_result_block_match"]
  end
ensure
  lock.close
end
