# frozen_string_literal: true

# Supplemental correctness checks only. Reuse the native launcher, containment,
# comparator and tolerances; never edit generated code or benchmark measurements.
require "csv"
require "find"
require "open3"
require "digest"
require "json"
require "fileutils"
require "time"
require "/tmp/beam10-opencode-evaluation-20261030.pAq8IE/experiment/lib/local_evaluation"

module UnstructuredBoundaryCheck
  extend self
  SCRATCH = __dir__
  EVIDENCE = "/home/petert/llm_para_campaigns/20261101-unstructured-boundary-validation"
  RELEASE = "/home/petert/llm-eval-local"
  SOURCE = "/home/petert/llm_para_experiments"
  BEAM_NATIVE = "/home/petert/llm_para_local_evaluation/20261030-beam10-opencode-validation"
  REFERENCE_REPO = "/tmp/beam10-opencode-evaluation-20261030.pAq8IE/benchmarks"
  REFERENCE_COMMIT = "2bc11aeac658a87b5cae25d03e0669f65d32922e"
  ARGS = %w[-v -r -n 32 -i 512].freeze
  KNOWN_BAD = "unstructured_beam-1.0-oc-medium_mpi_r2"
  CONTROLS = %w[unstructured_gpt-6.1-terra-medium_mpi_r1 unstructured_gpt-6.1-terra-medium_hybrid_r1].freeze

  def capture(*argv)
    out, err, status = Open3.capture3(*argv)
    raise "Command failed: #{argv.first}: #{err}" unless status.success?
    out
  end

  def sha(path) = Digest::SHA256.file(path).hexdigest
  def read_json(path) = JSON.parse(File.read(path))
  def write_json(path, data)
    raise "Evidence already exists: #{path}" if File.exist?(path)
    LocalEvaluation.atomic_write(path, JSON.pretty_generate(data) + "\n")
  end

  def source_files(repo, commit, prefix)
    raise "Unsafe source pin" unless commit.match?(/\A[0-9a-f]{40}\z/) && !prefix.split('/').include?('..') && !prefix.start_with?('/')
    paths = %w[unstructured common].map { |name| [prefix, name].reject(&:empty?).join('/') }
    capture("git", "-C", repo, "ls-tree", "-r", "-z", commit, "--", *paths).split("\0").filter_map do |entry|
      head, path = entry.split("\t", 2)
      mode, kind, oid = head.split
      next unless kind == "blob" && %w[100644 100755].include?(mode)
      relative = prefix.empty? ? path : path.delete_prefix(prefix + '/')
      parts = relative.split('/')
      next if parts[0...-1].any? { |name| LocalEvaluation::BuildSupport::GENERATED_DIRECTORY_RE.match?(name) }
      next if LocalEvaluation::BuildSupport::GENERATED_FILE_NAMES.include?(parts.last) || LocalEvaluation::BuildSupport::GENERATED_FILE_EXTENSIONS.include?(File.extname(relative))
      next if mode == "100755" && File.extname(relative).empty? && parts.last != "configure"
      [relative, oid]
    end.to_h
  end

  def matched_cache(row, repo: SOURCE)
    expected = source_files(repo, row.fetch("source_commit"), row.fetch("source_path"))
    raise "Empty source pin: #{row.fetch('id')}" if expected.empty?
    candidates = if row.fetch("id") == "sequential_reference"
      [File.join(BEAM_NATIVE, "validation/reference/unstructured")]
    else
      Dir["/home/petert/llm_para_local_evaluation/*/{validation,benchmark}/#{row.fetch('id')}"].sort.reverse
    end
    candidates.each do |directory|
      binary = File.join(directory, "unstructured")
      next unless File.file?(binary) && File.executable?(binary)
      next unless %w[build cmake].all? { |stage| File.file?(File.join(directory, "#{stage}_exitcode.log")) && File.read(File.join(directory, "#{stage}_exitcode.log")).strip == "0" }
      source_root = File.join(directory, "source")
      next unless File.directory?(source_root)
      actual = Dir[File.join(source_root, "**/*")].select { |path| File.file?(path) && !File.symlink?(path) }.to_h do |path|
        bytes = File.binread(path)
        [path.delete_prefix(source_root + '/'), Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0" + bytes)]
      end
      next unless actual == expected
      next if File.mtime(binary) > File.mtime(File.join(directory, "build_exitcode.log"))
      evidence_files = %w[source_staging.yaml cmake_command.log cmake_exitcode.log build_command.log build_exitcode.log build_wall_time.log]
      return row.merge("cache" => { "directory" => directory, "executable" => binary,
        "executable_sha256" => sha(binary), "staged_source_git_blob_ids" => expected,
        "build_evidence_sha256" => evidence_files.to_h { |name| [name, sha(File.join(directory, name))] },
        "reuse_basis" => "Exact Git-pinned staged source and CMake files, successful retained configure/build receipts, executable predating the completed build receipt. Binary hash captured now for immutable reuse." })
    end
    row.merge("cache" => nil, "staged_source_git_blob_ids" => expected)
  end

  def prepare
    raise "Inventory already prepared" if File.exist?(File.join(EVIDENCE, "manifest.json"))
    catalog_path = File.join(RELEASE, "release/catalog.json")
    csv_path = File.join(RELEASE, "release/scored_results.csv")
    catalog = read_json(catalog_path)
    # The original combined campaign spans multiple source batches. Later
    # replacement observations also have their own source commits.
    campaigns = {}
    catalog.fetch("campaigns").each do |campaign|
      CSV.foreach(File.join(RELEASE, campaign.fetch("aggregate_csv")), headers: true) do |row|
        id = [row["benchmark"], row["model"], row["par_type"], "r#{row['run']}"].join('_')
        raise "Duplicate campaign owner: #{id}" if campaigns.key?(id)
        campaigns[id] = campaign
      end
    end
    catalog.fetch("observation_replacements", []).each do |replacement|
      replacement.fetch("ids").each { |id| campaigns[id] = replacement }
    end
    rows = CSV.read(csv_path, headers: true).select do |row|
      row["benchmark"] == "unstructured" && %w[mpi hybrid].include?(row["par_type"]) && row["benchmark_success"] == "true"
    end.map do |row|
      fixed = row["timing_fixed"] == "true"
      id = [row["benchmark"], row["model"], row["par_type"], "r#{row['run']}"].join('_')
      pin = row[fixed ? "corrected_source_commit" : "original_source_commit"]
      pin = campaigns.fetch(id).fetch(fixed ? "corrected_source_commit" : "source_commit") if pin.to_s.empty?
      { "id" => id,
        "backend" => row["par_type"], "source_path" => row["source_path"], "source_commit" => pin,
        "origin" => "published_successful_measurement", "source_batch" => row["source_batch"], "timing_fixed" => fixed }
    end
    pipeline = LocalEvaluation::ValidationPipeline.new(run_dir: BEAM_NATIVE)
    pipeline.send(:load_results).values.select { |row| row.benchmark == "unstructured" && %w[mpi hybrid].include?(row.par_type) && row.output_comparison }.each do |row|
      rows << { "id" => row.id_string, "backend" => row.par_type,
        "source_path" => "20261025-170121/#{row.id_string}", "source_commit" => "74652eee82e2473660a7e75f3ad5d77fd0e3759c",
        "origin" => "beam_validation_pass", "source_batch" => "20261025-170121", "timing_fixed" => false }
    end
    raise "Scope differs" unless rows.size == 287 && rows.map { |r| r.fetch("id") }.uniq.size == rows.size
    matched = rows.sort_by { |row| row.fetch("id") }.map { |row| matched_cache(row) }
    reference = matched_cache({ "id" => "sequential_reference", "backend" => "sequential",
      "source_path" => "", "source_commit" => REFERENCE_COMMIT }, repo: REFERENCE_REPO)
    FileUtils.mkdir_p(EVIDENCE)
    LocalEvaluation.atomic_write(File.join(EVIDENCE, "inventory.jsonl"), matched.map { |row| JSON.generate(row) + "\n" }.join)
    write_json(File.join(EVIDENCE, "reference.json"), reference)
    FileUtils.cp(__FILE__, EVIDENCE)
    write_json(File.join(EVIDENCE, "manifest.json"), {
      "created_at" => Time.now.utc.iso8601, "records" => matched.size,
      "published_records" => 277, "beam_records" => 10, "arguments" => ARGS,
      "mpi_ranks" => 4, "timeout_seconds" => LocalEvaluation::ValidationPipeline::VALIDATION_TIMEOUT,
      "cached_builds_verified" => matched.count { |r| r["cache"] },
      "rebuild_required_ids" => matched.reject { |r| r["cache"] }.map { |r| r.fetch("id") },
      "reference_cached" => !!reference["cache"], "scratch" => SCRATCH,
      "release_commit" => capture("git", "-C", RELEASE, "rev-parse", "HEAD").strip,
      "catalog_sha256" => sha(catalog_path), "scored_csv_sha256" => sha(csv_path),
      "inventory_sha256" => sha(File.join(EVIDENCE, "inventory.jsonl")),
      "reference_sha256" => sha(File.join(EVIDENCE, "reference.json")), "driver_sha256" => sha(__FILE__),
      "native_pipeline" => LocalEvaluation.pipeline_source_snapshot,
      "scientific_policy" => "One additional boundary-crossing correctness case with unchanged native comparator/tolerances and four-rank validation resources. No model generation, algorithm edits, timing replacements or benchmark reruns. Retain ordinary failures without retry.",
      "approval" => "User approved the targeted supplemental validation on 2026-11-01."
    })
    puts JSON.pretty_generate(read_json(File.join(EVIDENCE, "manifest.json")))
  end

  def check_inputs
    manifest = read_json(File.join(EVIDENCE, "manifest.json"))
    raise "Driver changed" unless sha(__FILE__) == manifest.fetch("driver_sha256")
    raise "Inventory changed" unless sha(File.join(EVIDENCE, "inventory.jsonl")) == manifest.fetch("inventory_sha256")
    raise "Reference changed" unless sha(File.join(EVIDENCE, "reference.json")) == manifest.fetch("reference_sha256")
    raise "Arguments changed" unless manifest.fetch("arguments") == ARGS
    raise "Native pipeline changed" unless LocalEvaluation.pipeline_source_snapshot == manifest.fetch("native_pipeline")
    manifest
  end

  def execute(row, resources:, runner:, reference_output: nil)
    id = row.fetch("id")
    destination = File.join(EVIDENCE, "results", id)
    raise "Result already exists; use verified reuse" if File.exist?(destination)
    cache = row.fetch("cache")
    raise "Rebuild needed before execution: #{id}" unless cache
    raise "Cached executable changed" unless sha(cache.fetch("executable")) == cache.fetch("executable_sha256")
    cache.fetch("build_evidence_sha256").each { |name, digest| raise "Build evidence changed" unless sha(File.join(cache.fetch("directory"), name)) == digest }
    workspace = File.join(SCRATCH, "execution", id)
    FileUtils.mkdir_p(workspace)
    binary = File.join(workspace, "unstructured")
    FileUtils.cp(cache.fetch("executable"), binary, preserve: true)
    raise "Local executable copy differs" unless sha(binary) == cache.fetch("executable_sha256")
    env, command = if row.fetch("backend") == "sequential"
      [{ "CUDA_VISIBLE_DEVICES" => "", "OMP_NUM_THREADS" => "1" }, [binary, *ARGS]]
    else
      resources.command(par_type: row.fetch("backend"), executable: binary, args: ARGS, mode: :validation)
    end
    execution = runner.run(argv: command, env: env, prefix: File.join(destination, "validation_out"),
      chdir: workspace, timeout: LocalEvaluation::ValidationPipeline::VALIDATION_TIMEOUT,
      limits: LocalEvaluation::ExecutionLimits::VALIDATION)
    output = File.read(File.join(destination, "validation_out_stdout.log"))
    internal_ok = output.include?("Validation: PASSED") && !output.include?("Validation: FAILED") && !output.include?("Validation fail")
    comparison = execution.success && internal_ok && reference_output ? validate(reference_output, output, "unstructured") : nil
    passed = execution.success && internal_ok && (reference_output.nil? || comparison&.first == true)
    result = { "checked_at" => Time.now.utc.iso8601, "id" => id, "passed" => passed,
      "backend" => row.fetch("backend"), "source_commit" => row.fetch("source_commit"), "source_path" => row.fetch("source_path"),
      "executable_sha256" => cache.fetch("executable_sha256"), "arguments" => ARGS,
      "execution" => execution.to_h, "internal_validation" => internal_ok,
      "comparison" => comparison, "output_sha256" => sha(File.join(destination, "validation_out_stdout.log")),
      "scope" => "supplemental correctness only; no benchmark timing or native validation record overwritten" }
    write_json(File.join(destination, "result.json"), result)
    puts JSON.generate(result.slice("id", "passed", "backend").merge("wall_seconds" => execution.wall_seconds, "comparison" => comparison))
    [result, output]
  end

  def pilot
    check_inputs
    raise "Pilot already exists" if File.exist?(File.join(EVIDENCE, "pilot.json"))
    pids, _error, status = Open3.capture3("pgrep", "-u", "llmtest")
    raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
    lock = LocalEvaluation::HostPerformanceLock.new
    resources = LocalEvaluation::Resources.new
    resources.verify_topology!
    runner = LocalEvaluation::ProcessRunner.new
    reference_result, output = execute(read_json(File.join(EVIDENCE, "reference.json")), resources: resources, runner: runner)
    raise "Sequential reference failed" unless reference_result.fetch("passed")
    rows = File.readlines(File.join(EVIDENCE, "inventory.jsonl")).map { |line| JSON.parse(line) }.to_h { |row| [row.fetch("id"), row] }
    results = ([KNOWN_BAD] + CONTROLS).map { |id| execute(rows.fetch(id), resources: resources, runner: runner, reference_output: output).first }
    passed = results.find { |row| row.fetch("id") == KNOWN_BAD }.fetch("passed") == false &&
      results.select { |row| CONTROLS.include?(row.fetch("id")) }.all? { |row| row.fetch("passed") }
    report = { "checked_at" => Time.now.utc.iso8601, "passed" => passed, "arguments" => ARGS,
      "known_bad_rejected" => !results.first.fetch("passed"), "positive_controls_passed" => results.drop(1).all? { |row| row.fetch("passed") },
      "result_paths" => results.map { |row| File.join(EVIDENCE, "results", row.fetch("id"), "result.json") },
      "reference_result_sha256" => sha(File.join(EVIDENCE, "results/sequential_reference/result.json")),
      "model_requests" => 0, "algorithmic_edits" => 0, "benchmark_runs" => 0 }
    write_json(File.join(EVIDENCE, "pilot.json"), report)
    puts JSON.pretty_generate(report)
  ensure
    lock&.close
  end
end

if $PROGRAM_NAME == __FILE__
  raise "Use prepare or pilot" unless ARGV.size == 1 && %w[prepare pilot].include?(ARGV.first)
  UnstructuredBoundaryCheck.public_send(ARGV.first)
end
