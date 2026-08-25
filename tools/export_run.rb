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

  ORIGINAL_AMENDED_ATTEMPT_ID = "spmv_gpt-5.6-terra-low_hybrid_r2"
  TIMING_METHOD_FILES = %w[
    lib/timing_audit.rb
    lib/timing_fix.rb
    lib/timing_fix_adjudication.rb
    lib/timing_fix_finalize.rb
    lib/timing_fix_materializer.rb
    lib/timing_fix_review.rb
    finalize_scoring_metadata.rb
    scoring_threshold_review.rb
    scoped_measurement_rerun.rb
    timing_audit.rb
    timing_audit_prompt.txt
    timing_audit_schema.json
    timing_finalize_audit.rb
    timing_fix.rb
    timing_fix_adjudication.rb
    timing_fix_adjudication_import.rb
    timing_fix_adjudication_prompt.txt
    timing_fix_adjudication_schema.json
    timing_fix_finalize.rb
    timing_fix_materialize.rb
    timing_fix_prompt.txt
    timing_fix_review.rb
    timing_fix_review_prompt.txt
    timing_fix_review_schema.json
    timing_fix_schema.json
    timing_priority_review.rb
    timing_rerun_pilot_ids.txt
    timing_rerun_cleanup_ids.txt
    timing_rerun_status.rb
  ].freeze

  VALIDATION_FAILURE_LOG = /\A(?:cmake|build)_(?:command|stdout|stderr|exitcode|wall_time)\.log\z/
  VALIDATION_COMMAND_LOG = "validation_out_command.log"
  REFERENCE_FILE = /\A(?:cmake|build|validation_out)_(?:command|stdout|stderr|exitcode|wall_time)\.log\z/
  BENCHMARK_LOG = /\Abenchmark_(?:warmup|\d+)_(?:command|stdout|stderr|exitcode|wall_time|parse_error)\.log\z/
  INCIDENT_FILE = /\A(?:source_staging\.yaml|validation_metadata\.yaml|validation_result\.txt|validation_out_(?:command|stdout|stderr|exitcode|wall_time)\.log)\z/

  def initialize(options)
    @run_dir = File.expand_path(options.fetch(:run_dir))
    @replacement_run_dir = File.expand_path(options.fetch(:replacement_run_dir))
    @pipeline_root = File.expand_path(options.fetch(:pipeline_root))
    @baseline_root = File.expand_path(options.fetch(:baseline_root))
    @timing_audit_root = File.expand_path(options.fetch(:timing_audit_root))
    @timing_proposals_root = File.expand_path(options.fetch(:timing_proposals_root))
    @timing_review_root = File.expand_path(options.fetch(:timing_review_root))
    @timing_adjudication_root = File.expand_path(options.fetch(:timing_adjudication_root))
    @timing_final_root = File.expand_path(options.fetch(:timing_final_root))
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
      @pipeline_amendment_names = pipeline_amendment_names
      @pipeline_amendments = @pipeline_amendment_names.map do |name|
        [name, LocalEvalArtifact.load_yaml(path(@run_dir, name))]
      end
      @latest_pipeline_amendment_name, @latest_pipeline_amendment = @pipeline_amendments.last
      @source_correction_amendment = LocalEvalArtifact.load_yaml(path(@run_dir, "source_correction_amendment.yaml"))
      @source_correction_amendment_sha256 = LocalEvalArtifact.sha256(path(@run_dir, "source_correction_amendment.yaml"))
      @correction_records = LocalEvalArtifact.read_jsonl(path(@run_dir, "source_correction_records.jsonl"))
      @corrections_by_id = @correction_records.to_h { |record| [record.fetch("program_id"), record] }
      @baseline_benchmark_records = load_benchmark_records(@baseline_root)

      export_provenance
      export_calibration
      export_validation
      export_benchmark
      write_stage("data/provenance/run-history.md", run_history)
      export_aggregate_and_scoring
      export_pipeline_snapshot
      export_timing_method_snapshot
      export_timing_evidence
      validate_export!
      export_release_summary
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
      "baseline release" => @baseline_root,
      "timing audit" => @timing_audit_root,
      "timing proposals" => @timing_proposals_root,
      "timing post-fix review" => @timing_review_root,
      "timing adjudication" => @timing_adjudication_root,
      "timing final evidence" => @timing_final_root,
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
    names = %w[
      evaluation_manifest.yaml
      benchmark_seed.yaml
      benchmark_config.yaml
      scoring_metadata.yaml
      source_correction_amendment.yaml
      source_correction_evidence_manifest.yaml
      source_correction_ids.txt
      source_correction_records.jsonl
      scoped_measurement_rerun.yaml
      scoped_measurement_rerun_completion.yaml
    ] + pipeline_amendment_names
    names.each do |name|
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

    @pipeline_amendment_names.each do |name|
      copy_run_file(name, "data/provenance/amendments/#{name}")
      copy_run_file("#{name}.sha256", "data/provenance/amendments/#{name}.sha256")
    end

    %w[
      source_correction_amendment.yaml
      source_correction_amendment.yaml.sha256
      source_correction_evidence_manifest.yaml
      source_correction_evidence_manifest.yaml.sha256
      source_correction_ids.txt
      source_correction_ids.txt.sha256
      source_correction_records.jsonl
      source_correction_records.jsonl.sha256
    ].each do |name|
      copy_run_file(name, "data/provenance/source-correction/#{name}")
    end

    %w[
      scoped_measurement_rerun.yaml
      scoped_measurement_rerun.yaml.sha256
      scoped_measurement_rerun_completion.yaml
      scoped_measurement_rerun_completion.yaml.sha256
    ].each do |name|
      copy_run_file(name, "data/provenance/scoped-measurement-rerun/#{name}")
    end

    write_stage("data/provenance/repositories.yaml", YAML.dump(repository_provenance))
    write_stage("data/provenance/system.md", system_description)
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

      timing_fixed = metadata["timing_fixed"] == true
      correction = timing_fixed ? @corrections_by_id.fetch(id) : nil
      record = {
        "schema_version" => 2,
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
        "metrics" => metadata.fetch("metrics"),
        "timing_fixed" => timing_fixed,
        "timing_correction" => timing_fixed ? timing_correction_record(metadata, correction) : nil
      }
      if metadata.key?("pipeline_amendment_sha256")
        record["pipeline_amendment_sha256"] = metadata.fetch("pipeline_amendment_sha256")
      end

      @benchmark_records << record
      partitions[[record.fetch("benchmark"), record.fetch("backend")]] << record
      export_benchmark_failure_evidence(directory, record) unless record.fetch("success")
    end

    unless @benchmark_records.size == LocalEvalArtifact::EXPECTED.fetch(:benchmark_records)
      raise "benchmark export requires a quiescent complete run: found #{@benchmark_records.size}/#{LocalEvalArtifact::EXPECTED.fetch(:benchmark_records)} per-ID metadata records"
    end

    partitions.sort.each do |(benchmark, backend), records|
      destination = stage_path("data/benchmark/records/#{benchmark}/#{backend}.jsonl")
      LocalEvalArtifact.write_jsonl(destination, records.sort_by { |record| record.fetch("id") })
    end

    export_archived_attempts
    export_timing_rerun_comparison
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

    retained_root = path(attempts_root, ORIGINAL_AMENDED_ATTEMPT_ID)
    raise "missing retained original amended attempt: #{retained_root}" unless File.directory?(retained_root)

    Find.find(retained_root) do |source|
      next unless File.file?(source)

      name = File.basename(source)
      unless name == "benchmark_metadata.yaml" || BENCHMARK_LOG.match?(name)
        raise "unexpected archived-attempt artifact: #{source}"
      end
      relative = source.delete_prefix("#{attempts_root}/")
      copy_file(source, "data/benchmark/attempts/#{relative}")
    end
  end

  def timing_correction_record(metadata, correction)
    {
      "source_correction_amendment_sha256" => metadata.fetch("source_correction_amendment_sha256"),
      "issue_categories" => metadata.fetch("timing_fix_issue_categories"),
      "changed_paths" => metadata.fetch("timing_fix_changed_paths"),
      "original_source" => {
        "commit" => metadata.fetch("original_source_commit"),
        "digest" => metadata.fetch("original_source_digest"),
        "url" => correction.fetch("original_source_url")
      },
      "corrected_source" => {
        "commit" => metadata.fetch("corrected_source_commit"),
        "digest" => metadata.fetch("corrected_source_digest"),
        "url" => correction.fetch("corrected_source_url")
      },
      "build" => {
        "success" => metadata.fetch("build_success"),
        "error" => metadata["build_error"],
        "staged_source_content_sha256" => metadata.fetch("staged_source_content_sha256"),
        "temporary_workspace" => metadata.fetch("temporary_workspace")
      }
    }
  end

  def export_timing_rerun_comparison
    current_by_id = @benchmark_records.to_h { |record| [record.fetch("id"), record] }
    @timing_comparison_records = @correction_records.sort_by { |record| record.fetch("program_id") }.map do |correction|
      id = correction.fetch("program_id")
      prior = @baseline_benchmark_records.fetch(id)
      current = current_by_id.fetch(id)
      prior_measurement = benchmark_measurement(prior)
      current_measurement = benchmark_measurement(current)
      prior_median = prior_measurement["median_time_ms"]
      current_median = current_measurement["median_time_ms"]
      {
        "schema_version" => 1,
        "id" => id,
        "benchmark" => current.fetch("benchmark"),
        "model" => current.fetch("model"),
        "backend" => current.fetch("backend"),
        "repetition" => current.fetch("repetition"),
        "timing_fixed" => true,
        "source_correction_amendment_sha256" => @source_correction_amendment_sha256,
        "original_source_url" => correction.fetch("original_source_url"),
        "corrected_source_url" => correction.fetch("corrected_source_url"),
        "prior" => prior_measurement,
        "corrected" => current_measurement,
        "success_changed" => prior.fetch("success") != current.fetch("success"),
        "median_time_ratio" => prior_median && current_median ? current_median / prior_median : nil
      }
    end
    LocalEvalArtifact.write_jsonl(
      stage_path("data/timing-audit/rerun-comparison.jsonl"),
      @timing_comparison_records
    )

    affected = @corrections_by_id.keys.to_set
    current_unaffected = @benchmark_records.reject { |record| affected.include?(record.fetch("id")) }
    baseline_unaffected = @baseline_benchmark_records.values.reject { |record| affected.include?(record.fetch("id")) }
    @unaffected_current_sha256 = benchmark_records_digest(current_unaffected)
    @unaffected_baseline_sha256 = benchmark_records_digest(baseline_unaffected)
    assert_equal(
      @unaffected_baseline_sha256,
      @unaffected_current_sha256,
      "unaffected benchmark records"
    )
  end

  def benchmark_measurement(record)
    metrics = record.fetch("metrics")
    wall_seconds = record.fetch("wall_seconds")
    {
      "success" => record.fetch("success"),
      "metrics" => metrics,
      "median_time_ms" => median(metrics.map { |metric| Float(metric.fetch("time")) }),
      "wall_seconds" => wall_seconds,
      "median_wall_seconds" => median(wall_seconds.map { |value| Float(value) })
    }
  end

  def benchmark_records_digest(records)
    normalized = records.sort_by { |record| record.fetch("id") }.map do |record|
      value = JSON.parse(JSON.generate(record))
      value["schema_version"] = 2
      value["timing_fixed"] = false
      value["timing_correction"] = nil
      value
    end
    Digest::SHA256.hexdigest(normalized.map { |record| JSON.generate(canonicalize(record)) << "\n" }.join)
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
    when Array
      value.map { |element| canonicalize(element) }
    else
      value
    end
  end

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    midpoint = sorted.size / 2
    sorted.size.odd? ? sorted[midpoint] : (sorted[midpoint - 1] + sorted[midpoint]) / 2.0
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
    snapshot = @latest_pipeline_amendment.fetch("amended_pipeline_source")
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

  def export_timing_method_snapshot
    TIMING_METHOD_FILES.each do |relative|
      copy_file(path(@pipeline_root, relative), "method/timing-audit/#{relative}")
    end
    lines = TIMING_METHOD_FILES.sort.map do |relative|
      source = path(@pipeline_root, relative)
      "#{LocalEvalArtifact.sha256(source)}  timing-audit/#{relative}\n"
    end
    write_stage("method/timing-audit-files.sha256", lines.join)
  end

  def export_timing_evidence
    copy_evidence_files(
      @timing_audit_root,
      "data/timing-audit/static-audit/primary",
      %w[
        manifest.yaml prompt-template.txt result-schema.json runner-snapshot.rb
        summary-full.csv summary-full.jsonl trial-ids.txt
      ]
    )
    copy_evidence_files(
      path(@timing_audit_root, "final"),
      "data/timing-audit/static-audit/final",
      %w[
        correction-ids.txt decisions.csv decisions.jsonl manual-scope-overrides.yaml
        metadata.yaml
      ]
    )

    final_metadata = LocalEvalArtifact.load_yaml(path(@timing_audit_root, "final", "metadata.yaml"))
    priority_root = File.expand_path(final_metadata.fetch("roots").fetch("priority_review"))
    audit_adjudication_root = File.expand_path(final_metadata.fetch("roots").fetch("adjudication"))
    copy_evidence_files(
      priority_root,
      "data/timing-audit/static-audit/priority-review",
      %w[manifest.yaml comparison.csv comparison.jsonl priority-ids.txt priority-selection.jsonl]
    )
    copy_evidence_files(
      audit_adjudication_root,
      "data/timing-audit/static-audit/adjudication",
      %w[manifest.yaml]
    )
    Dir.glob(path(audit_adjudication_root, "results", "*.json")).sort.each do |source|
      copy_file(source, "data/timing-audit/static-audit/adjudication/results/#{File.basename(source)}")
    end

    copy_evidence_files(
      @timing_proposals_root,
      "data/timing-audit/corrections/proposals",
      %w[
        manifest.yaml manual-proposal-overrides.yaml prompt-template.txt proposal-schema.json
        runner-snapshot.rb summary-full.jsonl
      ]
    )
    copy_evidence_files(
      path(@timing_proposals_root, "materialized"),
      "data/timing-audit/corrections/materialization",
      %w[summary-full.yaml]
    )
    copy_evidence_files(
      @timing_review_root,
      "data/timing-audit/corrections/postfix-review",
      %w[
        manifest.yaml manual-result-overrides.yaml prompt-template.txt result-schema.json
        runner-snapshot.rb summary-full.csv summary-full.jsonl
      ]
    )
    copy_evidence_files(
      @timing_adjudication_root,
      "data/timing-audit/corrections/adjudication",
      %w[
        environment-evidence.yaml manifest.yaml manual-result-overrides.yaml
        prompt-template.txt result-schema.json runner-snapshot.rb summary-full.jsonl
      ]
    )
    copy_evidence_files(
      @timing_final_root,
      "data/timing-audit/corrections/final",
      %w[correction-ids.txt corrections.jsonl manifest.yaml]
    )

    evidence_files = LocalEvalArtifact.regular_files(stage_path("data/timing-audit"))
    lines = evidence_files.sort.map do |file|
      relative = LocalEvalArtifact.relative_path(stage_path("data/timing-audit"), file)
      next if relative == "evidence-files.sha256"

      "#{LocalEvalArtifact.sha256(file)}  #{relative}\n"
    end.compact
    write_stage("data/timing-audit/evidence-files.sha256", lines.join)
  end

  def copy_evidence_files(root, destination_root, relatives)
    raise "timing evidence root is not a directory: #{root}" unless File.directory?(root)

    relatives.each { |relative| copy_file(path(root, relative), "#{destination_root}/#{relative}") }
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
    @benchmark_successes = successful_benchmarks
    @benchmark_failures = benchmark_ids.size - successful_benchmarks

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

    correction_ids = @corrections_by_id.keys.sort
    timing_fixed_ids = @benchmark_records.select { |record| record.fetch("timing_fixed") }
                                         .map { |record| record.fetch("id") }.sort
    assert_equal(expected.fetch(:timing_corrections), correction_ids.size, "timing correction count")
    assert_equal(correction_ids, timing_fixed_ids, "timing-corrected benchmark IDs")
    assert_equal(expected.fetch(:timing_corrections), @timing_comparison_records.size, "timing rerun comparison count")
    assert_equal(@source_correction_amendment.fetch("affected_run_ids").sort, correction_ids, "source amendment IDs")

    verify_timing_evidence!
    verify_scoped_measurement_rerun!

    verify_derived_digest_chain!
    verify_scores!
  end

  def verify_timing_evidence!
    decisions = LocalEvalArtifact.read_jsonl(
      stage_path("data/timing-audit/static-audit/final/decisions.jsonl")
    )
    counts = decisions.each_with_object(Hash.new(0)) do |record, result|
      result[record.fetch("final_verdict")] += 1
    end
    assert_equal(LocalEvalArtifact::EXPECTED.fetch(:timing_audit_records), decisions.size, "timing audit count")
    assert_equal({ "valid" => 1_028, "invalid" => 587 }, counts.sort.to_h, "timing audit verdicts")
    invalid_ids = decisions.select { |record| record.fetch("final_verdict") == "invalid" }
                           .map { |record| record.fetch("program_id") }.sort
    assert_equal(@corrections_by_id.keys.sort, invalid_ids, "invalid audit/correction IDs")

    final_manifest = LocalEvalArtifact.load_yaml(
      stage_path("data/timing-audit/corrections/final/manifest.yaml")
    )
    assert_equal("accept", final_manifest.fetch("all_final_verdicts"), "final correction verdict")
    assert_equal(@correction_records.size, final_manifest.fetch("record_count"), "final correction records")
    assert_equal(
      @source_correction_amendment.fetch("source_evidence_manifest_sha256"),
      LocalEvalArtifact.sha256(stage_path("data/timing-audit/corrections/final/manifest.yaml")),
      "source amendment/final evidence manifest"
    )
  end

  def verify_scoped_measurement_rerun!
    amendment_path = path(@run_dir, "scoped_measurement_rerun.yaml")
    completion_path = path(@run_dir, "scoped_measurement_rerun_completion.yaml")
    @scoped_measurement_rerun = LocalEvalArtifact.load_yaml(amendment_path)
    @scoped_measurement_completion = LocalEvalArtifact.load_yaml(completion_path)
    ids = @scoped_measurement_rerun.fetch("affected_run_ids")
    assert_equal(ids.sort, ids, "scoped measurement rerun ID ordering")
    assert_equal([], ids - @corrections_by_id.keys, "scoped measurement rerun correction scope")
    assert_equal(ids, @scoped_measurement_completion.fetch("affected_run_ids"), "scoped measurement completion IDs")
    assert_equal(LocalEvalArtifact.sha256(amendment_path), @scoped_measurement_completion.fetch("amendment_sha256"), "scoped measurement amendment digest")
    assert_equal(true, @scoped_measurement_completion.fetch("unaffected_records_unchanged"), "scoped measurement unaffected guard")
    ids.each do |id|
      metadata_path = path(@run_dir, "benchmark", id, "benchmark_metadata.yaml")
      assert_equal(
        LocalEvalArtifact.sha256(metadata_path),
        @scoped_measurement_completion.dig("records", id, "benchmark_metadata_sha256"),
        "scoped measurement final metadata for #{id}"
      )
    end
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

    prior_digest = nil
    @pipeline_amendments.each_with_index do |(name, amendment), index|
      assert_equal(@manifest_sha256, amendment.fetch("manifest_sha256"), "amendment manifest for #{name}")
      if index.positive?
        assert_equal(prior_digest, amendment.fetch("prior_amendment_sha256"), "amendment chain for #{name}")
      end
      prior_digest = LocalEvalArtifact.sha256(path(@run_dir, name))
    end
    assert_equal(prior_digest, aggregate.fetch("pipeline_amendment_sha256"), "aggregate amendment")
    assert_equal(@source_correction_amendment_sha256, aggregate.fetch("source_correction_amendment_sha256"), "aggregate source correction")
    assert_equal(prior_digest, scoring.fetch("pipeline_amendment_sha256"), "scoring amendment")
    assert_equal(@source_correction_amendment_sha256, scoring.fetch("source_correction_amendment_sha256"), "scoring source correction")
    assert_equal(
      @latest_pipeline_amendment.dig("amended_pipeline_source", "sha256"),
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
    @score_counts = counts.sort.to_h
    scoring = LocalEvalArtifact.load_yaml(path(@run_dir, "scoring_metadata.yaml"))
    assert_equal(@score_counts, scoring.fetch("score_counts"), "scoring metadata distribution")
    assert_equal(rows, scoring.fetch("record_count"), "scoring metadata record count")
  end

  def export_release_summary
    audit_decisions = LocalEvalArtifact.read_jsonl(
      stage_path("data/timing-audit/static-audit/final/decisions.jsonl")
    )
    audit_counts = audit_decisions.each_with_object(Hash.new(0)) do |record, counts|
      counts[record.fetch("final_verdict")] += 1
    end
    comparison_successes = @timing_comparison_records.count do |record|
      record.fetch("corrected").fetch("success")
    end
    summary = {
      "schema_version" => 1,
      "canonical_run" => File.basename(@run_dir),
      "manifest_sha256" => @manifest_sha256,
      "benchmark_configuration_sha256" => LocalEvalArtifact.sha256(path(@run_dir, "benchmark_config.yaml")),
      "pipeline_amendments" => @pipeline_amendment_names.map do |name|
        { "file" => name, "sha256" => LocalEvalArtifact.sha256(path(@run_dir, name)) }
      end,
      "source_correction_amendment_sha256" => @source_correction_amendment_sha256,
      "scoped_measurement_rerun" => {
        "amendment_sha256" => LocalEvalArtifact.sha256(path(@run_dir, "scoped_measurement_rerun.yaml")),
        "completion_sha256" => LocalEvalArtifact.sha256(path(@run_dir, "scoped_measurement_rerun_completion.yaml")),
        "records" => @scoped_measurement_rerun.fetch("affected_run_ids").size,
        "unaffected_records_unchanged" => @scoped_measurement_completion.fetch("unaffected_records_unchanged")
      },
      "counts" => {
        "validation_records" => @validation_records.size,
        "fully_valid" => @validation_records.count { |record| LocalEvalArtifact.fully_valid?(record) },
        "benchmark_records" => @benchmark_records.size,
        "benchmark_successes" => @benchmark_successes,
        "benchmark_failures" => @benchmark_failures,
        "score_records" => LocalEvalArtifact::EXPECTED.fetch(:score_records),
        "score_counts" => @score_counts,
        "timing_audit_records" => audit_decisions.size,
        "timing_audit_verdicts" => audit_counts.sort.to_h,
        "timing_corrections" => @correction_records.size,
        "timing_correction_benchmark_successes" => comparison_successes,
        "timing_correction_benchmark_failures" => @correction_records.size - comparison_successes
      },
      "localized_rerun_guard" => {
        "unaffected_records" => @benchmark_records.size - @correction_records.size,
        "baseline_sha256" => @unaffected_baseline_sha256,
        "final_sha256" => @unaffected_current_sha256,
        "unchanged" => @unaffected_baseline_sha256 == @unaffected_current_sha256
      },
      "timing_rerun_comparison" => {
        "path" => "data/timing-audit/rerun-comparison.jsonl",
        "sha256" => LocalEvalArtifact.sha256(stage_path("data/timing-audit/rerun-comparison.jsonl")),
        "records" => @timing_comparison_records.size
      }
    }
    write_stage("data/release_summary.yaml", YAML.dump(summary))
  end

  def install_export!
    targets = [
      path(@output_root, "data"),
      path(@output_root, "method/pipeline"),
      path(@output_root, "method/pipeline-files.sha256"),
      path(@output_root, "method/timing-audit"),
      path(@output_root, "method/timing-audit-files.sha256")
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
    FileUtils.mv(stage_path("method/timing-audit"), path(@output_root, "method/timing-audit"))
    FileUtils.mv(stage_path("method/timing-audit-files.sha256"), path(@output_root, "method/timing-audit-files.sha256"))
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
        "final_pipeline_sha256" => @latest_pipeline_amendment.dig("amended_pipeline_source", "sha256"),
        "final_pipeline_amendment_sha256" => LocalEvalArtifact.sha256(path(@run_dir, @latest_pipeline_amendment_name)),
        "source_correction_amendment_sha256" => @source_correction_amendment_sha256,
        "benchmark_configuration_sha256" => LocalEvalArtifact.sha256(path(@run_dir, "benchmark_config.yaml"))
      },
      "generated_programs" => {
        "repository" => "https://github.com/PeterTh/llm-eval-generated",
        "commit" => @manifest.dig("experiment_repository", "commit"),
        "original_commit" => @source_correction_amendment.dig("original_experiment_repository", "commit"),
        "timing_corrected_commit" => @source_correction_amendment.dig("corrected_experiment_repository", "commit"),
        "artifact_path" => "<batch>/<run-id>",
        "join_keys" => %w[id batch content_sha256],
        "timing_correction_records" => "data/provenance/source-correction/source_correction_records.jsonl"
      },
      "benchmark_sources" => {
        "repository" => "https://github.com/PeterTh/llm-eval-benchmarks",
        "commit" => @manifest.dig("benchmark_repository", "commit")
      },
      "pipeline_source" => {
        "repository" => "https://github.com/PeterTh/llm-eval-experiment",
        "manifest_base_commit" => @manifest.dig("script_repository", "commit"),
        "final_sha256" => @latest_pipeline_amendment.dig("amended_pipeline_source", "sha256"),
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
    corrected_successes = @timing_comparison_records.count { |record| record.dig("corrected", "success") }

    <<~MARKDOWN
      # Run and Correction History

      ## Canonical run: `#{File.basename(@run_dir)}`

      The complete run contains #{@validation_records.size} validation records,
      #{@validation_records.count { |record| LocalEvalArtifact.fully_valid?(record) }} fully valid programs,
      #{@benchmark_records.size} benchmark attempts, #{@benchmark_successes} benchmark successes,
      #{@benchmark_failures} benchmark failures, and 4,620 canonical scores. Its manifest
      SHA-256 is `#{@manifest_sha256}` and frozen
      benchmark configuration SHA-256 is
      `#{LocalEvalArtifact.sha256(path(@run_dir, "benchmark_config.yaml"))}`.

      An initially successful SpMV record reported `0.000 ms` because generated code
      passed a float buffer to `MPI_Reduce` as `MPI_DOUBLE`. Two immutable amendments
      hardened positive-time parsing and isolated exact-ID resume reconciliation. Only
      `spmv_gpt-5.6-terra-low_hybrid_r2` was rerun; its prior attempt is preserved under
      `data/benchmark/attempts/`.

      A subsequent static audit examined all 1,615 successful MPI/hybrid programs under
      the maximum-completed-rank-time contract. It classified 1,028 timings as valid and
      587 as invalid. Timing-only corrections for those 587 programs were compiled,
      independently reviewed, committed together, and rerun without replacing unrelated
      results. #{corrected_successes} corrected benchmarks succeeded and
      #{@correction_records.size - corrected_successes} failed. All #{@benchmark_records.size - @correction_records.size} unrelated benchmark
      records retained their original digest. The prior attempt is preserved under
      the `local-eval-2026-08-22` Git tag; compact before/after measurements are in
      `data/timing-audit/rerun-comparison.jsonl`.

      Fifteen early records from the scoped batch were conservatively remeasured after
      brief qualification activity overlapped their execution window. The exact IDs,
      superseded-record digests, final-record digests, and unchanged-record guard are
      retained under `data/provenance/scoped-measurement-rerun/`.

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
      "benchmark_successes" => @benchmark_records.count { |record| record.fetch("success") },
      "timing_corrections" => @correction_records.size,
      "unaffected_records_unchanged" => @unaffected_baseline_sha256 == @unaffected_current_sha256
    )
  end

  def pipeline_amendment_names
    names = Dir.glob(path(@run_dir, "pipeline_amendment*.yaml")).map { |file| File.basename(file) }
    names.select! { |name| name == "pipeline_amendment.yaml" || name.match?(/\Apipeline_amendment\.\d+\.yaml\z/) }
    names.sort_by do |name|
      name == "pipeline_amendment.yaml" ? 1 : Integer(name.match(/\.(\d+)\.yaml\z/)[1], 10)
    end
  end

  def load_benchmark_records(root)
    paths = Dir.glob(path(root, "data/benchmark/records/*/*.jsonl")).sort
    raise "baseline release has no benchmark record partitions: #{root}" if paths.empty?

    records = paths.flat_map { |file| LocalEvalArtifact.read_jsonl(file) }
    by_id = records.to_h { |record| [record.fetch("id"), record] }
    raise "duplicate IDs in baseline benchmark records" unless by_id.size == records.size

    by_id
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
  opts.on("--baseline-root=PATH", "Prior release checkout used for localized-rerun comparison") { |value| options[:baseline_root] = value }
  opts.on("--timing-audit-root=PATH", "Final static timing-audit workspace") { |value| options[:timing_audit_root] = value }
  opts.on("--timing-proposals-root=PATH", "Timing-fix proposal workspace") { |value| options[:timing_proposals_root] = value }
  opts.on("--timing-review-root=PATH", "Independent post-fix review workspace") { |value| options[:timing_review_root] = value }
  opts.on("--timing-adjudication-root=PATH", "Post-fix adjudication workspace") { |value| options[:timing_adjudication_root] = value }
  opts.on("--timing-final-root=PATH", "Compact finalized timing-correction evidence") { |value| options[:timing_final_root] = value }
  opts.on("--output=PATH", "Destination repository (default: repository root)") { |value| options[:output] = value }
  opts.on("--replace", "Replace an existing managed export") { options[:replace] = true }
end

parser.parse!
missing = %i[
  run_dir replacement_run_dir pipeline_root baseline_root timing_audit_root
  timing_proposals_root timing_review_root timing_adjudication_root timing_final_root
].reject { |key| options.key?(key) }
abort parser.to_s unless missing.empty?

ArtifactExporter.new(options).run
