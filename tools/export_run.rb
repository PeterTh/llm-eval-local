#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "find"
require "json"
require "open3"
require "optparse"
require "tmpdir"

require_relative "artifact_common"

class ArtifactExporter
  include LocalEvalArtifact

  VALIDATION_FAILURE_LOG = /\A(?:cmake|build)_(?:command|stdout|stderr|exitcode|wall_time)\.log\z/
  VALIDATION_COMMAND_LOG = "validation_out_command.log"
  REFERENCE_FILE = /\A(?:cmake|build|validation_out)_(?:command|stdout|stderr|exitcode|wall_time)\.log\z/
  BENCHMARK_LOG = /\Abenchmark_(?:warmup|\d+)_(?:command|stdout|stderr|exitcode|wall_time|parse_error)\.log\z/
  INCIDENT_FILE = /\A(?:source_staging\.yaml|validation_metadata\.yaml|validation_result\.txt|validation_out_(?:command|stdout|stderr|exitcode|wall_time)\.log)\z/

  def initialize(options)
    @run_dir = File.expand_path(options.fetch(:run_dir))
    @replacement_run_dir = File.expand_path(options.fetch(:replacement_run_dir))
    @pipeline_root = File.expand_path(options.fetch(:pipeline_root))
    @output_root = File.expand_path(options.fetch(:output))
    @replace = options.fetch(:replace)
    @validation_records = []
    @benchmark_records = []
  end

  def run
    validate_inputs!
    verify_original_sidecars!

    Dir.mktmpdir("llm-eval-artifact-", "/tmp") do |temporary_root|
      @stage_root = temporary_root
      @manifest = LocalEvalArtifact.load_yaml(path(@run_dir, "evaluation_manifest.yaml"))
      @manifest_sha256 = LocalEvalArtifact.sha256(path(@run_dir, "evaluation_manifest.yaml"))
      @amendment_one = LocalEvalArtifact.load_yaml(path(@run_dir, "pipeline_amendment.yaml"))
      @amendment_two = LocalEvalArtifact.load_yaml(path(@run_dir, "pipeline_amendment.2.yaml"))

      export_provenance
      export_calibration
      export_validation
      export_benchmark
      export_aggregate_and_scoring
      export_pipeline_snapshot
      validate_export!
      install_export!
    end

    write_global_checksums!
    print_summary
  end

  private

  def validate_inputs!
    {
      "canonical run" => @run_dir,
      "replacement run" => @replacement_run_dir,
      "pipeline root" => @pipeline_root,
      "output repository" => @output_root
    }.each do |label, directory|
      raise "#{label} is not a directory: #{directory}" unless File.directory?(directory)
    end
    raise "output is not a Git working tree: #{@output_root}" unless File.directory?(path(@output_root, ".git"))
    raise "canonical and replacement run must differ" if @run_dir == @replacement_run_dir
    raise "refusing NFS temporary storage" if network_filesystem?("/tmp")
    raise "refusing NFS persistent repository" if network_filesystem?(@output_root)
  end

  def network_filesystem?(directory)
    output, status = Open3.capture2("stat", "-f", "-c", "%T", directory)
    raise "cannot determine filesystem for #{directory}" unless status.success?

    output.strip.match?(/nfs|cifs|smb|fuse\.sshfs/i)
  end

  def verify_original_sidecars!
    %w[
      evaluation_manifest.yaml
      benchmark_seed.yaml
      benchmark_config.yaml
      pipeline_amendment.yaml
      pipeline_amendment.2.yaml
      scoring_metadata.yaml
    ].each do |name|
      file = path(@run_dir, name)
      sidecar = "#{file}.sha256"
      raise "missing original file: #{file}" unless File.file?(file)
      raise "missing original sidecar: #{sidecar}" unless File.file?(sidecar)
      expected = LocalEvalArtifact.parse_sidecar(sidecar)
      actual = LocalEvalArtifact.sha256(file)
      raise "original sidecar mismatch for #{name}: #{expected} != #{actual}" unless expected == actual
    end
  end

  def export_provenance
    copy_run_file("evaluation_manifest.yaml", "data/provenance/evaluation_manifest.yaml")
    copy_run_file("evaluation_manifest.yaml.sha256", "data/provenance/evaluation_manifest.yaml.sha256")
    copy_run_file("preflight.yaml", "data/provenance/preflight/init.yaml")
    copy_run_file("validation/preflight.yaml", "data/provenance/preflight/validation.yaml")
    copy_run_file("benchmark/preflight.yaml", "data/provenance/preflight/benchmark.yaml")

    %w[pipeline_amendment.yaml pipeline_amendment.2.yaml].each do |name|
      copy_run_file(name, "data/provenance/amendments/#{name}")
      copy_run_file("#{name}.sha256", "data/provenance/amendments/#{name}.sha256")
    end

    write_stage("data/provenance/repositories.yaml", YAML.dump(repository_provenance))
    write_stage("data/provenance/system.md", system_description)
    write_stage("data/provenance/run-history.md", run_history)
    export_incident
  end

  def export_calibration
    {
      "benchmark_seed.yaml" => "data/calibration/benchmark_seed.yaml",
      "benchmark_seed.yaml.sha256" => "data/calibration/benchmark_seed.yaml.sha256",
      "benchmark_config.proposed.yaml" => "data/calibration/benchmark_config.proposed.yaml",
      "benchmark_config.yaml" => "data/calibration/benchmark_config.yaml",
      "benchmark_config.yaml.sha256" => "data/calibration/benchmark_config.yaml.sha256"
    }.each { |source, destination| copy_run_file(source, destination) }

    review_root = path(@run_dir, "calibration_review")
    Dir.glob(path(review_root, "**/review_probe.yaml")).sort.each do |source|
      relative = source.delete_prefix("#{review_root}/")
      copy_file(source, "data/calibration/manual-review/#{relative}")
    end
  end

  def export_validation
    copy_run_file(
      "validation/all_validation_results.yaml",
      "data/validation/all_validation_results.yaml"
    )

    partitions = Hash.new { |hash, key| hash[key] = [] }
    metadata_paths = Dir.glob(path(@run_dir, "validation/*/validation_metadata.yaml")).sort
    metadata_paths.each do |metadata_path|
      directory = File.dirname(metadata_path)
      id = File.basename(directory)
      metadata = LocalEvalArtifact.load_yaml(metadata_path)
      source_staging = LocalEvalArtifact.load_yaml(path(directory, "source_staging.yaml"))
      manifest_run = @manifest.fetch("runs").fetch(id)

      source = {
        "batch" => manifest_run.fetch("batch"),
        "path" => "#{manifest_run.fetch("batch")}/#{id}",
        "content_sha256" => source_staging.fetch("content_sha256"),
        "copied_files" => source_staging.fetch("copied_files"),
        "seen_entries" => source_staging.fetch("seen_entries"),
        "copied_bytes" => source_staging.fetch("copied_bytes"),
        "skipped_generated_entries" => source_staging.fetch("skipped_generated_entries", [])
      }

      record = {
        "schema_version" => 1,
        "id" => id,
        "benchmark" => metadata.fetch("benchmark"),
        "model" => metadata.fetch("model"),
        "backend" => metadata.fetch("par_type"),
        "repetition" => metadata.fetch("run"),
        "manifest_sha256" => metadata.fetch("manifest_sha256"),
        "completed_at" => metadata.fetch("completed_at"),
        "source" => source,
        "stages" => metadata.fetch("stages"),
        "result" => LocalEvalArtifact.read_utf8(path(directory, "validation_result.txt")),
        "execution" => validation_execution(directory)
      }
      @validation_records << record
      partitions[[record.fetch("benchmark"), record.fetch("backend")]] << record

      export_validation_failure_evidence(directory, record) unless LocalEvalArtifact.fully_valid?(record)
    end

    partitions.sort.each do |(benchmark, backend), records|
      destination = stage_path("data/validation/records/#{benchmark}/#{backend}.jsonl")
      LocalEvalArtifact.write_jsonl(destination, records.sort_by { |record| record.fetch("id") })
    end

    export_reference_evidence
  end

  def validation_execution(directory)
    stdout_path = path(directory, "validation_out_stdout.log")
    return nil unless File.file?(stdout_path)

    {
      "stdout" => LocalEvalArtifact.read_utf8(stdout_path),
      "stderr" => LocalEvalArtifact.read_utf8(path(directory, "validation_out_stderr.log")),
      "exit_code" => parse_optional_integer(path(directory, "validation_out_exitcode.log")),
      "wall_seconds" => parse_optional_float(path(directory, "validation_out_wall_time.log"))
    }
  end

  def export_validation_failure_evidence(directory, record)
    Dir.children(directory).sort.each do |name|
      next unless VALIDATION_FAILURE_LOG.match?(name) || name == VALIDATION_COMMAND_LOG

      destination = "data/validation/failures/#{record.fetch("benchmark")}/#{record.fetch("id")}/#{name}"
      copy_file(path(directory, name), destination)
    end
  end

  def export_reference_evidence
    reference_root = path(@run_dir, "validation/reference")
    Find.find(reference_root) do |source|
      next unless File.file?(source)

      name = File.basename(source)
      next unless %w[source_staging.yaml reference_metadata.yaml].include?(name) || REFERENCE_FILE.match?(name)

      relative = source.delete_prefix("#{reference_root}/")
      copy_file(source, "data/validation/references/#{relative}")
    end
  end

  def export_benchmark
    {
      "benchmark/benchmark_full_results.yaml" => "data/benchmark/benchmark_full_results.yaml",
      "benchmark/benchmark_results.yaml" => "data/benchmark/benchmark_results.yaml",
      "benchmark/benchmark_run_metadata.yaml" => "data/benchmark/benchmark_run_metadata.yaml"
    }.each { |source, destination| copy_run_file(source, destination) }

    partitions = Hash.new { |hash, key| hash[key] = [] }
    metadata_paths = Dir.glob(path(@run_dir, "benchmark/*/benchmark_metadata.yaml")).sort
    metadata_paths.each do |metadata_path|
      directory = File.dirname(metadata_path)
      id = File.basename(directory)
      metadata = LocalEvalArtifact.load_yaml(metadata_path)
      run = metadata.fetch("run")

      record = {
        "schema_version" => 1,
        "id" => id,
        "benchmark" => run.fetch("benchmark"),
        "model" => run.fetch("model"),
        "backend" => run.fetch("par_type"),
        "repetition" => run.fetch("run"),
        "batch" => run.fetch("batch"),
        "source_path" => "#{run.fetch("batch")}/#{id}",
        "args" => metadata.fetch("args"),
        "timeout_seconds" => metadata.fetch("timeout_seconds"),
        "configuration_sha256" => metadata.fetch("configuration_sha256"),
        "wall_seconds" => metadata.fetch("wall_seconds"),
        "warmup_wall_seconds" => metadata["warmup_wall_seconds"],
        "all_execution_wall_seconds" => metadata.fetch("all_execution_wall_seconds"),
        "executions" => metadata.fetch("executions"),
        "success" => metadata.fetch("success"),
        "metrics" => metadata.fetch("metrics")
      }
      if metadata.key?("pipeline_amendment_sha256")
        record["pipeline_amendment_sha256"] = metadata.fetch("pipeline_amendment_sha256")
      end

      @benchmark_records << record
      partitions[[record.fetch("benchmark"), record.fetch("backend")]] << record
      export_benchmark_failure_evidence(directory, record) unless record.fetch("success")
    end

    partitions.sort.each do |(benchmark, backend), records|
      destination = stage_path("data/benchmark/records/#{benchmark}/#{backend}.jsonl")
      LocalEvalArtifact.write_jsonl(destination, records.sort_by { |record| record.fetch("id") })
    end

    export_archived_attempts
  end

  def export_benchmark_failure_evidence(directory, record)
    Dir.children(directory).sort.each do |name|
      next unless BENCHMARK_LOG.match?(name)

      destination = "data/benchmark/failures/#{record.fetch("benchmark")}/#{record.fetch("id")}/#{name}"
      copy_file(path(directory, name), destination)
    end
  end

  def export_archived_attempts
    attempts_root = path(@run_dir, "benchmark/attempts")
    return unless File.directory?(attempts_root)

    Find.find(attempts_root) do |source|
      next unless File.file?(source)

      name = File.basename(source)
      unless name == "benchmark_metadata.yaml" || BENCHMARK_LOG.match?(name)
        raise "unexpected archived-attempt artifact: #{source}"
      end
      relative = source.delete_prefix("#{attempts_root}/")
      copy_file(source, "data/benchmark/attempts/#{relative}")
    end
  end

  def export_aggregate_and_scoring
    {
      "aggregate_results.yaml" => "data/aggregate/aggregate_results.yaml",
      "aggregate_results.csv" => "data/aggregate/aggregate_results.csv",
      "aggregate_metadata.yaml" => "data/aggregate/aggregate_metadata.yaml",
      "aggregate_parse_warnings.yaml" => "data/aggregate/aggregate_parse_warnings.yaml",
      "scored_results.yaml" => "data/scoring/scored_results.yaml",
      "scored_results.csv" => "data/scoring/scored_results.csv",
      "scoring_metadata.yaml" => "data/scoring/scoring_metadata.yaml",
      "scoring_metadata.yaml.sha256" => "data/scoring/scoring_metadata.yaml.sha256",
      "local_scoring_distributions.csv" => "data/scoring/local_scoring_distributions.csv",
      "local_scoring_thresholds.csv" => "data/scoring/local_scoring_thresholds.csv",
      "local_scoring_thresholds.proposed.csv" => "data/scoring/local_scoring_thresholds.proposed.csv",
      "local_scoring_threshold_review.yaml" => "data/scoring/local_scoring_threshold_review.yaml"
    }.each { |source, destination| copy_run_file(source, destination) }
  end

  def export_pipeline_snapshot
    snapshot = @amendment_two.fetch("amended_pipeline_source")
    snapshot.fetch("files").sort.each do |relative, expected_sha256|
      source = path(@pipeline_root, relative)
      actual_sha256 = LocalEvalArtifact.sha256(source)
      unless actual_sha256 == expected_sha256
        raise "pipeline file changed since final amendment: #{relative} (#{actual_sha256} != #{expected_sha256})"
      end
      copy_file(source, "method/pipeline/#{relative}")
    end

    lines = snapshot.fetch("files").sort.map do |relative, sha256|
      "#{sha256}  pipeline/#{relative}\n"
    end
    write_stage("method/pipeline-files.sha256", lines.join)
  end

  def export_incident
    id = "cahn-hilliard_gpt-5.6-terra-xhigh_hybrid_r1"
    roots = { "canonical" => @run_dir, "replacement" => @replacement_run_dir }
    staging_digests = []

    roots.each do |label, root|
      directory = path(root, "validation", id)
      raise "missing incident directory: #{directory}" unless File.directory?(directory)

      Dir.children(directory).sort.each do |name|
        next unless INCIDENT_FILE.match?(name)

        copy_file(
          path(directory, name),
          "data/provenance/incidents/cahn-hilliard-nondeterminism/#{label}/#{name}"
        )
      end
      staging = LocalEvalArtifact.load_yaml(path(directory, "source_staging.yaml"))
      staging_digests << staging.fetch("content_sha256")
    end
    raise "incident source snapshots differ" unless staging_digests.uniq.one?

    write_stage(
      "data/provenance/incidents/cahn-hilliard-nondeterminism/README.md",
      incident_description(id, staging_digests.first)
    )
  end

  def validate_export!
    expected = LocalEvalArtifact::EXPECTED
    validation_ids = @validation_records.map { |record| record.fetch("id") }
    benchmark_ids = @benchmark_records.map { |record| record.fetch("id") }
    fully_valid_ids = @validation_records.select { |record| LocalEvalArtifact.fully_valid?(record) }
                                         .map { |record| record.fetch("id") }
    successful_benchmarks = @benchmark_records.count { |record| record.fetch("success") }

    assert_equal(expected.fetch(:validation_records), validation_ids.size, "validation record count")
    assert_equal(validation_ids.size, validation_ids.uniq.size, "unique validation IDs")
    assert_equal(@manifest.fetch("runs").keys.sort, validation_ids.sort, "manifest/validation IDs")
    assert_equal(expected.fetch(:fully_valid), fully_valid_ids.size, "fully-valid count")
    assert_equal(expected.fetch(:benchmark_records), benchmark_ids.size, "benchmark record count")
    assert_equal(benchmark_ids.size, benchmark_ids.uniq.size, "unique benchmark IDs")
    assert_equal(fully_valid_ids.sort, benchmark_ids.sort, "fully-valid/benchmark IDs")
    assert_equal(expected.fetch(:benchmark_successes), successful_benchmarks, "benchmark success count")
    assert_equal(expected.fetch(:benchmark_failures), benchmark_ids.size - successful_benchmarks, "benchmark failure count")

    validation_partitions = Dir.glob(stage_path("data/validation/records/*/*.jsonl"))
    benchmark_partitions = Dir.glob(stage_path("data/benchmark/records/*/*.jsonl"))
    assert_equal(44, validation_partitions.size, "validation partition count")
    assert_equal(44, benchmark_partitions.size, "benchmark partition count")

    config_sha256 = LocalEvalArtifact.parse_sidecar(path(@run_dir, "benchmark_config.yaml.sha256"))
    @benchmark_records.each do |record|
      assert_equal(config_sha256, record.fetch("configuration_sha256"), "benchmark configuration digest for #{record.fetch("id")}")
      if record.fetch("success")
        assert_equal(5, record.fetch("metrics").size, "metric count for #{record.fetch("id")}")
        assert_equal(5, record.fetch("wall_seconds").size, "wall count for #{record.fetch("id")}")
      end
    end

    verify_derived_digest_chain!
    verify_scores!
  end

  def verify_derived_digest_chain!
    aggregate = LocalEvalArtifact.load_yaml(path(@run_dir, "aggregate_metadata.yaml"))
    scoring = LocalEvalArtifact.load_yaml(path(@run_dir, "scoring_metadata.yaml"))
    expected_files = {
      "validation_results_sha256" => path(@run_dir, "validation/all_validation_results.yaml"),
      "benchmark_full_results_sha256" => path(@run_dir, "benchmark/benchmark_full_results.yaml"),
      "benchmark_config_sha256" => path(@run_dir, "benchmark_config.yaml"),
      "aggregate_results_sha256" => path(@run_dir, "aggregate_results.yaml")
    }
    expected_files.each do |field, source|
      assert_equal(LocalEvalArtifact.sha256(source), aggregate.fetch(field), "aggregate #{field}")
    end

    scoring_files = {
      "aggregate_results_sha256" => path(@run_dir, "aggregate_results.yaml"),
      "distribution_sha256" => path(@run_dir, "local_scoring_distributions.csv"),
      "thresholds_sha256" => path(@run_dir, "local_scoring_thresholds.csv"),
      "threshold_review_sha256" => path(@run_dir, "local_scoring_threshold_review.yaml"),
      "scored_csv_sha256" => path(@run_dir, "scored_results.csv"),
      "scored_yaml_sha256" => path(@run_dir, "scored_results.yaml")
    }
    scoring_files.each do |field, source|
      assert_equal(LocalEvalArtifact.sha256(source), scoring.fetch(field), "scoring #{field}")
    end

    amendment_one_sha256 = LocalEvalArtifact.sha256(path(@run_dir, "pipeline_amendment.yaml"))
    amendment_two_sha256 = LocalEvalArtifact.sha256(path(@run_dir, "pipeline_amendment.2.yaml"))
    assert_equal(@manifest_sha256, @amendment_one.fetch("manifest_sha256"), "first amendment manifest")
    assert_equal(amendment_one_sha256, @amendment_two.fetch("prior_amendment_sha256"), "amendment chain")
    assert_equal(amendment_two_sha256, scoring.fetch("pipeline_amendment_sha256"), "scoring amendment")
    assert_equal(
      @amendment_two.dig("amended_pipeline_source", "sha256"),
      scoring.fetch("pipeline_source_sha256"),
      "final pipeline digest"
    )
  end

  def verify_scores!
    counts = Hash.new(0)
    rows = 0
    CSV.foreach(path(@run_dir, "scored_results.csv"), headers: true) do |row|
      rows += 1
      counts[Integer(row.fetch("overall_score"), 10)] += 1
    end
    assert_equal(LocalEvalArtifact::EXPECTED.fetch(:score_records), rows, "score record count")
    assert_equal(LocalEvalArtifact::EXPECTED.fetch(:score_counts), counts.sort.to_h, "score distribution")
  end

  def install_export!
    targets = [
      path(@output_root, "data"),
      path(@output_root, "method/pipeline"),
      path(@output_root, "method/pipeline-files.sha256")
    ]
    occupied = targets.select { |target| File.exist?(target) }
    unless occupied.empty? || @replace
      raise "managed export already exists; pass --replace to replace it: #{occupied.join(", ")}"
    end

    targets.each do |target|
      if File.directory?(target)
        FileUtils.rm_rf(target)
      else
        FileUtils.rm_f(target)
      end
    end
    FileUtils.mkdir_p(path(@output_root, "method"))
    FileUtils.mv(stage_path("data"), path(@output_root, "data"))
    FileUtils.mv(stage_path("method/pipeline"), path(@output_root, "method/pipeline"))
    FileUtils.mv(stage_path("method/pipeline-files.sha256"), path(@output_root, "method/pipeline-files.sha256"))
  end

  def write_global_checksums!
    checksum_path = path(@output_root, "checksums.sha256")
    files = LocalEvalArtifact.regular_files(@output_root).reject { |file| file == checksum_path }
    lines = files.map do |file|
      "#{LocalEvalArtifact.sha256(file)}  #{LocalEvalArtifact.relative_path(@output_root, file)}\n"
    end
    File.write(checksum_path, lines.join, mode: "wb")
  end

  def repository_provenance
    {
      "schema_version" => 1,
      "canonical_run" => {
        "id" => File.basename(@run_dir),
        "manifest_sha256" => @manifest_sha256,
        "final_pipeline_sha256" => @amendment_two.dig("amended_pipeline_source", "sha256"),
        "benchmark_configuration_sha256" => LocalEvalArtifact.sha256(path(@run_dir, "benchmark_config.yaml"))
      },
      "generated_programs" => {
        "repository" => "https://github.com/PeterTh/llm-eval-generated",
        "commit" => @manifest.dig("experiment_repository", "commit"),
        "artifact_path" => "<batch>/<run-id>",
        "join_keys" => %w[id batch content_sha256]
      },
      "benchmark_sources" => {
        "repository" => "https://github.com/PeterTh/llm-eval-benchmarks",
        "commit" => @manifest.dig("benchmark_repository", "commit")
      },
      "pipeline_source" => {
        "repository" => "https://github.com/PeterTh/llm-eval-experiment",
        "manifest_base_commit" => @manifest.dig("script_repository", "commit"),
        "final_sha256" => @amendment_two.dig("amended_pipeline_source", "sha256"),
        "snapshot" => "method/pipeline",
        "file_checksums" => "method/pipeline-files.sha256"
      }
    }
  end

  def system_description
    environment = @manifest.fetch("environment")
    profiles = @manifest.fetch("resource_profiles")
    preflight = LocalEvalArtifact.load_yaml(path(@run_dir, "preflight.yaml"))
    rows = profiles.flat_map do |mode, backends|
      backends.map { |backend, description| "| #{mode} | #{backend} | #{description} |" }
    end

    <<~MARKDOWN
      # Execution System

      This is the system recorded by the immutable manifest and live launcher preflights
      for canonical run `#{File.basename(@run_dir)}`. Raw initialization, validation, and
      benchmark preflights are retained under `preflight/`.

      ## Hardware

      - Host identifier: `#{environment.fetch("hostname")}`
      - Physical cores available to the pipeline: #{preflight.fetch("physical_cores")}
      - NUMA nodes: #{preflight.fetch("numa_nodes").join(", ")}
      - GPUs: four NVIDIA GeForce RTX 3090 devices, 24,576 MiB each
      - Persistent run storage: local NVMe-backed XFS under `/home`
      - Free space recorded at initialization: #{preflight.fetch("free_disk_bytes")} bytes
      - Cgroup containment enabled: #{preflight.fetch("cgroup_containment")}

      ## Toolchain

      - #{environment.fetch("ruby")}
      - #{environment.fetch("cmake")}
      - C compiler: #{environment.fetch("cc")}
      - C++ compiler: #{environment.fetch("cxx")}
      - CUDA compiler: #{environment.fetch("nvcc")}
      - MPI: #{environment.fetch("mpi")}

      ## Resource profiles

      | Phase | Backend | Effective resources |
      |---|---|---|
      #{rows.join("\n")}

      ## CPU topology (`lscpu`)

      ```text
      #{environment.fetch("lscpu")}
      ```

      ## GPU inventory

      ```text
      #{environment.fetch("gpus")}
      ```

      Generated configure/build/run processes were executed in transient user-systemd
      scopes. Builds were limited to 32 GiB/256 tasks, validation to 64 GiB/256 tasks,
      and calibration/benchmarking to 256 GiB/512 tasks. Stdout and stderr were drained
      with an 8 MiB retained cap; process-tree timeouts and TERM/KILL cleanup remained
      active. The operator kept unrelated load off the system during performance runs.
    MARKDOWN
  end

  def run_history
    replacement_metadata = Dir.glob(path(@replacement_run_dir, "validation/*/validation_metadata.yaml"))
    replacement_valid = replacement_metadata.count do |metadata_path|
      metadata = LocalEvalArtifact.load_yaml(metadata_path)
      metadata.fetch("stages").values.all? { |value| value == true }
    end
    scoring = LocalEvalArtifact.load_yaml(path(@run_dir, "scoring_metadata.yaml"))

    <<~MARKDOWN
      # Run and Correction History

      ## Canonical run: `#{File.basename(@run_dir)}`

      The complete run contains 4,620 validation records, 3,825 fully valid programs,
      3,825 benchmark attempts, 3,488 benchmark successes, 337 benchmark failures, and
      4,620 canonical scores. Its manifest SHA-256 is `#{@manifest_sha256}` and frozen
      benchmark configuration SHA-256 is
      `#{LocalEvalArtifact.sha256(path(@run_dir, "benchmark_config.yaml"))}`.

      An initially successful SpMV record reported `0.000 ms` because generated code
      passed a float buffer to `MPI_Reduce` as `MPI_DOUBLE`. Two immutable amendments
      hardened positive-time parsing and isolated exact-ID resume reconciliation. Only
      `spmv_gpt-5.6-terra-low_hybrid_r2` was rerun; all 3,824 unrelated benchmark
      records retained their original digest. The prior attempt is preserved under
      `data/benchmark/attempts/`.

      Final scored YAML SHA-256: `#{scoring.fetch("scored_yaml_sha256")}`.

      ## Interrupted diagnostic runs

      - `20260818-182827` was stopped after 2,027 validations because the then-current
        detector rejected four genuine CUDA-library answers. Its pipeline digest is
        intentionally stale and none of its corpus records are published here.
      - `#{File.basename(@replacement_run_dir)}` was an unnecessary full replacement
        started before the localized-rerun policy was clarified. It was cleanly stopped
        at #{replacement_metadata.size}/4,620 validations (#{replacement_valid} fully
        valid). Its one important new observation—the nondeterministic Cahn-Hilliard
        outcome—is retained as a scoped incident; unrelated duplicate records are not.

      ## Qualification evidence

      The final host-enabled suite passed 70 runs / 520 assertions with no failures,
      errors, or skips. A four-profile end-to-end canary completed validation,
      calibration, benchmarking, aggregation, and scoring. Its diagnostic thresholds
      and scores had no scientific meaning and therefore are summarized here rather
      than copied as another dataset.
    MARKDOWN
  end

  def incident_description(id, source_digest)
    replacement_manifest = LocalEvalArtifact.sha256(path(@replacement_run_dir, "evaluation_manifest.yaml"))
    <<~MARKDOWN
      # Nondeterministic Cahn-Hilliard validation

      Record `#{id}` used identical staged source (`#{source_digest}`) and equivalent
      validation commands in the canonical and interrupted replacement runs. The
      canonical execution conserved the reference sum and passed comparison; the
      replacement execution produced a concentration sum differing by about 0.0288 and
      failed comparison.

      Inspection found a generated-program race: the CUDA interior update includes
      planes adjacent to each MPI rank boundary and reads boundary chemical potentials
      produced concurrently on another stream without a synchronization dependency.
      This is a program-specific nondeterministic outcome, not a systemic launcher or
      validation defect. It therefore did not justify replacing unrelated results.

      - canonical manifest: `#{@manifest_sha256}`
      - replacement manifest: `#{replacement_manifest}`
      - retained evidence: source-staging metadata, validation metadata/result, command,
        stdout, stderr, exit code, and wall time from both executions
    MARKDOWN
  end

  def print_summary
    files = LocalEvalArtifact.regular_files(@output_root)
    bytes = files.sum { |file| File.size(file) }
    puts JSON.pretty_generate(
      "output" => @output_root,
      "files" => files.size,
      "logical_bytes" => bytes,
      "validation_records" => @validation_records.size,
      "fully_valid" => @validation_records.count { |record| LocalEvalArtifact.fully_valid?(record) },
      "benchmark_records" => @benchmark_records.size,
      "benchmark_successes" => @benchmark_records.count { |record| record.fetch("success") }
    )
  end

  def parse_optional_integer(file)
    text = LocalEvalArtifact.read_utf8(file).strip
    text.empty? ? nil : Integer(text, 10)
  end

  def parse_optional_float(file)
    text = LocalEvalArtifact.read_utf8(file).strip
    text.empty? ? nil : Float(text)
  end

  def assert_equal(expected, actual, label)
    return if expected == actual

    raise "#{label} mismatch: expected #{expected.inspect}, got #{actual.inspect}"
  end

  def copy_run_file(source_relative, destination_relative)
    copy_file(path(@run_dir, source_relative), destination_relative)
  end

  def copy_file(source, destination_relative)
    raise "missing source file: #{source}" unless File.file?(source)
    raise "refusing source symlink: #{source}" if File.symlink?(source)

    destination = stage_path(destination_relative)
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(source, destination)
    File.chmod(0o644, destination)
  end

  def write_stage(relative, content)
    destination = stage_path(relative)
    FileUtils.mkdir_p(File.dirname(destination))
    File.write(destination, content, mode: "wb")
    File.chmod(0o644, destination)
  end

  def stage_path(relative)
    candidate = File.expand_path(relative, @stage_root)
    prefix = "#{File.expand_path(@stage_root)}/"
    raise "unsafe stage path: #{relative}" unless candidate.start_with?(prefix)

    candidate
  end

  def path(root, *parts)
    File.join(root, *parts)
  end
end

options = {
  output: File.expand_path("..", __dir__),
  replace: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby tools/export_run.rb [options]"
  opts.on("--run-dir=PATH", "Canonical completed run directory") { |value| options[:run_dir] = value }
  opts.on("--replacement-run-dir=PATH", "Interrupted replacement run containing incident evidence") do |value|
    options[:replacement_run_dir] = value
  end
  opts.on("--pipeline-root=PATH", "Pipeline source working tree") { |value| options[:pipeline_root] = value }
  opts.on("--output=PATH", "Destination repository (default: repository root)") { |value| options[:output] = value }
  opts.on("--replace", "Replace an existing managed export") { options[:replace] = true }
end

parser.parse!
missing = %i[run_dir replacement_run_dir pipeline_root].reject { |key| options.key?(key) }
abort parser.to_s unless missing.empty?

ArtifactExporter.new(options).run
