#!/usr/bin/env ruby
# frozen_string_literal: true

# Bounded causal diagnostic, separate from canonical validation/benchmark data.
# Prepare baseline and scalar source trees from the review's pinned Git source;
# apply the retained scalar-loop.patch only to the latter before invoking this.
require "json"
require "digest"
require "optparse"
require "fileutils"
require "time"
options = {}
OptionParser.new do |parser|
  %w[pipeline workspace output].each { |key| parser.on("--#{key}=PATH") { |value| options[key] = File.expand_path(value) } }
end.parse!
raise "Specify --pipeline, --workspace and --output" unless options.keys.sort == %w[output pipeline workspace] && ARGV.empty?
require File.join(options.fetch("pipeline"), "lib/local_evaluation")
workspace = options.fetch("workspace")
raise "Workspace must be on local /tmp" unless workspace.start_with?("/tmp/")
output = options.fetch("output")
raise "Refusing to overwrite diagnostic evidence" if File.exist?(output)
root = File.expand_path("../..", __dir__)
id = "spmv_gpt-6.1-sol-xhigh_mpi_r2"
context = JSON.parse(File.read(File.join(root, "analysis/notes/2026-10-11-sol61-winner-context.json")))
pin = context.fetch("source_pins").fetch(id)
before = "spmvLocal(localVal.data(), localCols.data(), localRowDelimiters.data(),"
after = "spmvCpu(localVal.data(), localCols.data(), localRowDelimiters.data(),"
pin.fetch("files").each do |relative, expected|
  baseline = File.binread(File.join(workspace, "baseline", relative))
  scalar = File.binread(File.join(workspace, "scalar", relative))
  raise "Baseline source changed" unless Digest::SHA256.hexdigest(baseline) == expected
  if relative == "spmv/spmv.cpp"
    raise "Scalar diagnostic is not the single intended change" unless baseline.scan(before).size == 1 && scalar == baseline.sub(before, after)
  else
    raise "Non-kernel source changed" unless scalar == baseline
  end
end
config = LocalEvaluation.load_yaml(File.join(root, "batches/20261006-204623/benchmark/provenance/benchmark_config.yaml"))
cell = config.fetch("cells").fetch("mpi").fetch("spmv")
args = cell.fetch("args").map(&:to_s)
raise "Diagnostic configuration changed" unless args == %w[-n 10000 -s 40 -i 50000]
report = { "schema_version" => 1, "program_id" => id, "source_commit" => pin.fetch("commit"),
  "purpose" => "Isolate four-row interleaving by substituting the existing scalar CSR routine. Diagnostic only; canonical results and scores are unchanged.",
  "started_at" => Time.now.utc.iso8601, "benchmark_args" => args,
  "correctness_args" => %w[-n 10000 -s 40 -i 1 -v -r],
  "pipeline_source_sha256" => LocalEvaluation.pipeline_source_snapshot.fetch("sha256"),
  "resource_profile" => LocalEvaluation.resource_profile_description.fetch("benchmark").fetch("mpi"),
  "patch" => "2026-10-11-sol61-spmv-diagnostic/scalar-loop.patch",
  "patch_sha256" => Digest::SHA256.file(File.join(root, "analysis/notes/2026-10-11-sol61-spmv-diagnostic/scalar-loop.patch")).hexdigest,
  "variants" => {}, "executions" => [] }
save = -> { LocalEvaluation.atomic_write(output, JSON.pretty_generate(report) + "\n") }
runner = LocalEvaluation::ProcessRunner.new
lock = LocalEvaluation::HostPerformanceLock.new
begin
  %w[baseline scalar].each do |variant|
    source = File.join(workspace, variant, "spmv")
    build = File.join(workspace, "builds", variant)
    success, error = LocalEvaluation::BuildSupport.build(source_dir: source, build_dir: build, runner: runner, par_type: "mpi")
    report.fetch("variants")[variant] = {
      "source_sha256" => Digest::SHA256.file(File.join(source, "spmv.cpp")).hexdigest,
      "build_success" => success, "build_error" => error,
      "build_logs" => Dir[File.join(build, "{cmake,build}_*.log")].sort.to_h { |p| [File.basename(p), File.read(p)] },
      "times_ms" => [] }
    save.call
    raise error unless success
    report.fetch("variants").fetch(variant)["executable_sha256"] = Digest::SHA256.file(File.join(build, "spmv")).hexdigest
  end
  execute = lambda do |variant, label, execution_args|
    executable = File.join(workspace, "builds", variant, "spmv")
    env, command = LocalEvaluation::Resources.new.command(par_type: "mpi", executable: executable, args: execution_args, mode: :benchmark)
    prefix = File.join(workspace, "logs", "#{variant}-#{label}")
    result = runner.run(argv: command, env: env, prefix: prefix, timeout: cell.fetch("timeout_seconds"),
      chdir: workspace, limits: LocalEvaluation::ExecutionLimits::PERFORMANCE)
    stdout = File.read("#{prefix}_stdout.log")
    row = { "variant" => variant, "label" => label, "args" => execution_args, "success" => result.success,
      "exit_code" => result.exit_code, "timed_out" => result.timed_out, "wall_seconds" => result.wall_seconds,
      "stdout" => stdout, "stderr" => File.read("#{prefix}_stderr.log"), "command" => File.read("#{prefix}_command.log") }
    report.fetch("executions") << row
    save.call
    raise "Diagnostic failed: #{variant}/#{label}" unless result.success && !result.timed_out && !result.output_truncated
    row["reported_ms"] = LocalEvaluation::BenchmarkMetrics.parse("spmv", stdout).fetch("time")
    puts "#{variant}/#{label}: #{row.fetch('reported_ms')} ms"
    $stdout.flush
    row
  end
  checks = %w[baseline scalar].map { |variant| execute.call(variant, "correctness", report.fetch("correctness_args")) }
  raise "Internal diagnostic correctness failed" unless checks.all? { |row| row.fetch("stdout").include?("Validation: PASSED") }
  passed, message = validate(checks.first.fetch("stdout"), checks.last.fetch("stdout"), "spmv")
  report["correctness_comparison"] = { "passed" => passed, "message" => message,
    "scope" => "Both variants' internal sequential checks and unchanged numerical comparator at the full matrix size, one iteration. This diagnostic does not replace native validation." }
  save.call
  raise "Diagnostic numerical comparison failed" unless passed
  %w[baseline scalar].each { |variant| execute.call(variant, "warmup", args) }
  # Alternate order to limit monotonic drift; do not run concurrent diagnostics.
  [%w[baseline scalar], %w[scalar baseline], %w[baseline scalar]].each_with_index do |order, index|
    order.each do |variant|
      row = execute.call(variant, "measurement-#{index + 1}", args)
      report.fetch("variants").fetch(variant).fetch("times_ms") << row.fetch("reported_ms")
      save.call
    end
  end
  report.fetch("variants").each_value { |variant| variant["median_ms"] = variant.fetch("times_ms").sort.fetch(1) }
  report["completed_at"] = Time.now.utc.iso8601
  report["execution_count"] = report.fetch("executions").size
  save.call
ensure
  lock.close
end
