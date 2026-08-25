#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

require_relative "artifact_common"

class ReleaseVerifier
  MIB = 1024 * 1024
  MAX_FILE_BYTES = 10 * MIB
  MAX_DATA_BYTES = 60 * MIB
  MAX_ANALYSIS_BYTES = 20 * MIB
  MAX_TREE_BYTES = 100 * MIB

  DISALLOWED_EXTENSIONS = %w[
    .a .bin .c .cc .cpp .cu .cubin .d .dll .dylib .exe .fatbin .h .hpp .ii .o .obj
    .out .ptx .so
  ].freeze
  DISALLOWED_COMPONENTS = %w[CMakeFiles build bin source].freeze
  VALIDATION_KEYS = %w[
    schema_version id benchmark model backend repetition manifest_sha256 completed_at
    source stages result execution
  ].freeze
  BENCHMARK_REQUIRED_KEYS = %w[
    schema_version id benchmark model backend repetition batch source_path args
    timeout_seconds configuration_sha256 wall_seconds warmup_wall_seconds
    all_execution_wall_seconds executions success metrics timing_fixed timing_correction
  ].freeze

  def initialize(root)
    @root = File.expand_path(root)
    @errors = []
  end

  def run
    check("repository structure") { verify_structure }
    check("global checksums") { verify_global_checksums }
    check("budgets and artifact policy") { verify_budgets_and_policy }
    check("schemas") { verify_schema_documents }
    check("provenance and digest chains") { verify_provenance }
    check("validation records") { verify_validation_records }
    check("benchmark records") { verify_benchmark_records }
    check("canonical benchmark maps") { verify_canonical_benchmark_maps }
    check("timing audit and corrections") { verify_timing_audit_and_corrections }
    check("scores") { verify_scores }
    check("evidence scope") { verify_evidence_scope }
    check("incident evidence") { verify_incident }

    unless @errors.empty?
      warn "Artifact verification failed (#{@errors.size} checks):"
      @errors.each { |error| warn "- #{error}" }
      exit 1
    end

    files = LocalEvalArtifact.regular_files(@root)
    bytes = files.sum { |file| File.size(file) }
    puts "Artifact verification passed"
    puts "  files: #{files.size}"
    puts "  logical bytes: #{bytes}"
    puts "  validation: #{@validation_records.size} records, #{@fully_valid_ids.size} fully valid"
    puts "  benchmark: #{@benchmark_records.size} records, #{@benchmark_success_ids.size} successful"
    puts "  scores: #{@score_rows} records"
  end

  private

  def check(label)
    yield
  rescue StandardError => e
    @errors << "#{label}: #{e.message}"
  end

  def verify_structure
    %w[
      README.md RETENTION.md CITATION.cff checksums.sha256
      data/release_summary.yaml
      data/provenance/evaluation_manifest.yaml
      data/provenance/source-correction/source_correction_amendment.yaml
      data/provenance/source-correction/source_correction_records.jsonl
      data/provenance/scoped-measurement-rerun/scoped_measurement_rerun.yaml
      data/provenance/scoped-measurement-rerun/scoped_measurement_rerun_completion.yaml
      data/calibration/benchmark_config.yaml
      data/validation/all_validation_results.yaml
      data/benchmark/benchmark_full_results.yaml
      data/aggregate/aggregate_results.yaml
      data/scoring/scored_results.csv
      data/timing-audit/static-audit/final/decisions.jsonl
      data/timing-audit/corrections/final/corrections.jsonl
      data/timing-audit/rerun-comparison.jsonl
      method/pipeline-files.sha256
      method/timing-audit-files.sha256
      schemas/validation-record.schema.json
      schemas/benchmark-record.schema.json
      schemas/timing-rerun-comparison-record.schema.json
    ].each { |relative| require_file(relative) }
  end

  def verify_global_checksums
    manifest_path = file("checksums.sha256")
    entries = {}
    File.foreach(manifest_path, chomp: true).with_index(1) do |line, line_number|
      match = line.match(/\A([0-9a-f]{64})  (.+)\z/)
      raise "malformed line #{line_number}" unless match
      digest = match[1]
      relative = match[2]
      ensure_safe_relative!(relative)
      raise "duplicate checksum entry: #{relative}" if entries.key?(relative)
      entries[relative] = digest
    end

    actual_files = LocalEvalArtifact.regular_files(@root).reject { |path| path == manifest_path }
    actual_relatives = actual_files.map { |path| LocalEvalArtifact.relative_path(@root, path) }.sort
    raise "checksum file set differs from repository file set" unless entries.keys.sort == actual_relatives

    entries.each do |relative, expected|
      actual = LocalEvalArtifact.sha256(file(relative))
      raise "checksum mismatch: #{relative}" unless actual == expected
    end
  end

  def verify_budgets_and_policy
    files = LocalEvalArtifact.regular_files(@root)
    total = files.sum { |path| File.size(path) }
    data_total = subtree_bytes("data")
    analysis_total = subtree_bytes("analysis")
    raise "tracked tree exceeds #{MAX_TREE_BYTES} bytes: #{total}" if total > MAX_TREE_BYTES
    raise "data exceeds #{MAX_DATA_BYTES} bytes: #{data_total}" if data_total > MAX_DATA_BYTES
    raise "analysis exceeds #{MAX_ANALYSIS_BYTES} bytes: #{analysis_total}" if analysis_total > MAX_ANALYSIS_BYTES

    files.each do |path|
      relative = LocalEvalArtifact.relative_path(@root, path)
      size = File.size(path)
      raise "file exceeds #{MAX_FILE_BYTES} bytes: #{relative} (#{size})" if size > MAX_FILE_BYTES

      components = relative.split("/")
      bad_component = components.find { |component| DISALLOWED_COMPONENTS.include?(component) }
      raise "disallowed artifact directory #{bad_component}: #{relative}" if bad_component
      raise "disallowed Makefile: #{relative}" if File.basename(relative) == "Makefile"

      extension = File.extname(relative).downcase
      raise "disallowed artifact/source extension #{extension}: #{relative}" if DISALLOWED_EXTENSIONS.include?(extension)

      File.open(path, "rb") do |stream|
        raise "ELF binary detected: #{relative}" if stream.read(4) == "\x7FELF".b
      end
    end
  end

  def verify_schema_documents
    %w[
      validation-record.schema.json benchmark-record.schema.json
      timing-rerun-comparison-record.schema.json
    ].each do |name|
      schema = JSON.parse(File.read(file("schemas/#{name}"), encoding: Encoding::UTF_8))
      raise "schema declaration missing: #{name}" unless schema["$schema"]
      raise "schema type is not object: #{name}" unless schema["type"] == "object"
    end
  end

  def verify_provenance
    amendment_relatives = pipeline_amendment_relatives
    sidecar_pairs = %w[
      data/provenance/evaluation_manifest.yaml
      data/calibration/benchmark_seed.yaml
      data/calibration/benchmark_config.yaml
      data/scoring/scoring_metadata.yaml
      data/provenance/source-correction/source_correction_amendment.yaml
      data/provenance/source-correction/source_correction_evidence_manifest.yaml
      data/provenance/source-correction/source_correction_ids.txt
      data/provenance/source-correction/source_correction_records.jsonl
      data/provenance/scoped-measurement-rerun/scoped_measurement_rerun.yaml
      data/provenance/scoped-measurement-rerun/scoped_measurement_rerun_completion.yaml
    ] + amendment_relatives
    sidecar_pairs.each { |relative| verify_sidecar(relative) }

    @release_summary = LocalEvalArtifact.load_yaml(file("data/release_summary.yaml"))
    @manifest = LocalEvalArtifact.load_yaml(file("data/provenance/evaluation_manifest.yaml"))
    @manifest_sha256 = LocalEvalArtifact.sha256(file("data/provenance/evaluation_manifest.yaml"))
    @configuration_sha256 = LocalEvalArtifact.sha256(file("data/calibration/benchmark_config.yaml"))
    @pipeline_amendments = amendment_relatives.map do |relative|
      [relative, LocalEvalArtifact.load_yaml(file(relative))]
    end
    prior_digest = nil
    @pipeline_amendments.each_with_index do |(relative, amendment), index|
      equal!(@manifest_sha256, amendment.fetch("manifest_sha256"), "manifest for #{relative}")
      equal!(prior_digest, amendment.fetch("prior_amendment_sha256"), "chain for #{relative}") if index.positive?
      prior_digest = LocalEvalArtifact.sha256(file(relative))
    end
    @latest_amendment_relative, @latest_amendment = @pipeline_amendments.last
    @latest_amendment_sha256 = prior_digest

    correction_root = "data/provenance/source-correction"
    correction_amendment_relative = "#{correction_root}/source_correction_amendment.yaml"
    @source_correction_amendment = LocalEvalArtifact.load_yaml(file(correction_amendment_relative))
    @source_correction_amendment_sha256 = LocalEvalArtifact.sha256(file(correction_amendment_relative))
    @correction_records = LocalEvalArtifact.read_jsonl(file("#{correction_root}/source_correction_records.jsonl"))
    @corrections_by_id = @correction_records.to_h { |record| [record.fetch("program_id"), record] }
    raise "duplicate source-correction IDs" unless @corrections_by_id.size == @correction_records.size
    correction_ids = File.readlines(file("#{correction_root}/source_correction_ids.txt"), chomp: true)
    equal!(@corrections_by_id.keys.sort, correction_ids, "source-correction ID file")
    equal!(@source_correction_amendment.fetch("affected_run_ids").sort, correction_ids, "source-correction amendment IDs")
    equal!(
      LocalEvalArtifact.sha256(file("#{correction_root}/source_correction_records.jsonl")),
      @source_correction_amendment.fetch("records_sha256"),
      "source-correction records digest"
    )
    equal!(
      LocalEvalArtifact.sha256(file("#{correction_root}/source_correction_ids.txt")),
      @source_correction_amendment.fetch("ids_sha256"),
      "source-correction IDs digest"
    )

    repositories = LocalEvalArtifact.load_yaml(file("data/provenance/repositories.yaml"))
    equal!(@manifest.dig("experiment_repository", "commit"), repositories.dig("generated_programs", "commit"), "generated-program commit")
    equal!(@source_correction_amendment.dig("corrected_experiment_repository", "commit"), repositories.dig("generated_programs", "timing_corrected_commit"), "corrected generated-program commit")
    equal!(@manifest.dig("benchmark_repository", "commit"), repositories.dig("benchmark_sources", "commit"), "benchmark-source commit")
    equal!(@configuration_sha256, repositories.dig("canonical_run", "benchmark_configuration_sha256"), "repository configuration digest")
    equal!(@latest_amendment.dig("amended_pipeline_source", "sha256"), repositories.dig("pipeline_source", "final_sha256"), "repository pipeline digest")
    equal!(@latest_amendment_sha256, repositories.dig("canonical_run", "final_pipeline_amendment_sha256"), "repository amendment digest")
    equal!(@source_correction_amendment_sha256, repositories.dig("canonical_run", "source_correction_amendment_sha256"), "repository source-correction digest")

    verify_pipeline_snapshot
    verify_timing_method_snapshot
    verify_aggregate_and_scoring_digests
    verify_release_summary_provenance
    verify_scoped_measurement_rerun
  end

  def verify_pipeline_snapshot
    expected_files = @latest_amendment.dig("amended_pipeline_source", "files")
    pipeline_root = file("method/pipeline")
    actual = LocalEvalArtifact.regular_files(pipeline_root).to_h do |path|
      [LocalEvalArtifact.relative_path(pipeline_root, path), LocalEvalArtifact.sha256(path)]
    end
    equal!(expected_files, actual, "pipeline snapshot files")

    listed = parse_checksum_list(file("method/pipeline-files.sha256"), base: file("method"))
    expected_list = expected_files.to_h { |relative, digest| ["pipeline/#{relative}", digest] }
    equal!(expected_list, listed, "pipeline checksum manifest")
  end

  def verify_timing_method_snapshot
    parse_checksum_list(file("method/timing-audit-files.sha256"), base: file("method"))
  end

  def verify_aggregate_and_scoring_digests
    aggregate = LocalEvalArtifact.load_yaml(file("data/aggregate/aggregate_metadata.yaml"))
    scoring = LocalEvalArtifact.load_yaml(file("data/scoring/scoring_metadata.yaml"))
    aggregate_files = {
      "validation_results_sha256" => "data/validation/all_validation_results.yaml",
      "benchmark_full_results_sha256" => "data/benchmark/benchmark_full_results.yaml",
      "benchmark_config_sha256" => "data/calibration/benchmark_config.yaml",
      "aggregate_results_sha256" => "data/aggregate/aggregate_results.yaml"
    }
    aggregate_files.each do |field, relative|
      equal!(LocalEvalArtifact.sha256(file(relative)), aggregate.fetch(field), "aggregate #{field}")
    end

    scoring_files = {
      "aggregate_results_sha256" => "data/aggregate/aggregate_results.yaml",
      "distribution_sha256" => "data/scoring/local_scoring_distributions.csv",
      "thresholds_sha256" => "data/scoring/local_scoring_thresholds.csv",
      "threshold_review_sha256" => "data/scoring/local_scoring_threshold_review.yaml",
      "scored_csv_sha256" => "data/scoring/scored_results.csv",
      "scored_yaml_sha256" => "data/scoring/scored_results.yaml"
    }
    scoring_files.each do |field, relative|
      equal!(LocalEvalArtifact.sha256(file(relative)), scoring.fetch(field), "scoring #{field}")
    end

    equal!(@manifest_sha256, scoring.fetch("manifest_sha256"), "scoring manifest")
    equal!(@configuration_sha256, scoring.fetch("benchmark_config_sha256"), "scoring configuration")
    equal!(@latest_amendment_sha256, aggregate.fetch("pipeline_amendment_sha256"), "aggregate amendment")
    equal!(@source_correction_amendment_sha256, aggregate.fetch("source_correction_amendment_sha256"), "aggregate source correction")
    equal!(@latest_amendment_sha256, scoring.fetch("pipeline_amendment_sha256"), "scoring amendment")
    equal!(@source_correction_amendment_sha256, scoring.fetch("source_correction_amendment_sha256"), "scoring source correction")
    equal!(@latest_amendment.dig("amended_pipeline_source", "sha256"), scoring.fetch("pipeline_source_sha256"), "scoring pipeline")
  end


  def verify_release_summary_provenance
    equal!(@manifest_sha256, @release_summary.fetch("manifest_sha256"), "release-summary manifest")
    equal!(@configuration_sha256, @release_summary.fetch("benchmark_configuration_sha256"), "release-summary configuration")
    equal!(@source_correction_amendment_sha256, @release_summary.fetch("source_correction_amendment_sha256"), "release-summary source correction")
    summary_amendments = @release_summary.fetch("pipeline_amendments")
    expected = @pipeline_amendments.map do |relative, _amendment|
      { "file" => File.basename(relative), "sha256" => LocalEvalArtifact.sha256(file(relative)) }
    end
    equal!(expected, summary_amendments, "release-summary amendment chain")
  end

  def verify_scoped_measurement_rerun
    root = "data/provenance/scoped-measurement-rerun"
    amendment_path = file("#{root}/scoped_measurement_rerun.yaml")
    completion_path = file("#{root}/scoped_measurement_rerun_completion.yaml")
    amendment = LocalEvalArtifact.load_yaml(amendment_path)
    completion = LocalEvalArtifact.load_yaml(completion_path)
    ids = amendment.fetch("affected_run_ids")
    equal!(ids.sort, ids, "scoped measurement rerun ID ordering")
    raise "scoped measurement rerun escapes timing-correction scope" unless (ids - @corrections_by_id.keys).empty?
    equal!(ids, completion.fetch("affected_run_ids"), "scoped measurement completion IDs")
    equal!(LocalEvalArtifact.sha256(amendment_path), completion.fetch("amendment_sha256"), "scoped measurement amendment digest")
    raise "scoped measurement unrelated-record guard failed" unless completion.fetch("unaffected_records_unchanged") == true
    summary = @release_summary.fetch("scoped_measurement_rerun")
    equal!(LocalEvalArtifact.sha256(amendment_path), summary.fetch("amendment_sha256"), "scoped measurement summary amendment")
    equal!(LocalEvalArtifact.sha256(completion_path), summary.fetch("completion_sha256"), "scoped measurement summary completion")
    equal!(ids.size, summary.fetch("records"), "scoped measurement summary count")
  end

  def verify_validation_records
    @validation_records = load_partitioned_records("data/validation/records")
    expected = LocalEvalArtifact::EXPECTED
    equal!(expected.fetch(:validation_records), @validation_records.size, "validation record count")

    ids = @validation_records.map { |record| record.fetch("id") }
    equal!(ids.size, ids.uniq.size, "unique validation IDs")
    equal!(@manifest.fetch("runs").keys.sort, ids.sort, "manifest/validation IDs")

    @validation_records.each do |record|
      require_partition_match!(record, "data/validation/records")
      equal!(VALIDATION_KEYS.sort, record.keys.sort, "validation keys for #{record.fetch("id")}")
      equal!(1, record.fetch("schema_version"), "validation schema version")
      require_backend!(record)
      raise "invalid validation repetition: #{record.fetch("id")}" unless record.fetch("repetition").is_a?(Integer) && record.fetch("repetition").positive?
      raise "invalid validation manifest digest: #{record.fetch("id")}" unless LocalEvalArtifact::SHA256_RE.match?(record.fetch("manifest_sha256"))
      equal!(@manifest_sha256, record.fetch("manifest_sha256"), "validation manifest for #{record.fetch("id")}")
      equal!(LocalEvalArtifact::VALIDATION_STAGES.sort, record.fetch("stages").keys.sort, "validation stages for #{record.fetch("id")}")
      raise "validation result is not text: #{record.fetch("id")}" unless record.fetch("result").is_a?(String)

      source = record.fetch("source")
      raise "invalid source digest: #{record.fetch("id")}" unless LocalEvalArtifact::SHA256_RE.match?(source.fetch("content_sha256"))
      expected_path = "#{source.fetch("batch")}/#{record.fetch("id")}"
      equal!(expected_path, source.fetch("path"), "portable source path for #{record.fetch("id")}")
      if record.fetch("stages").fetch("validation_run") == true
        execution = record.fetch("execution")
        raise "missing validation execution: #{record.fetch("id")}" unless execution.is_a?(Hash)
        raise "missing validation stdout: #{record.fetch("id")}" unless execution.fetch("stdout").is_a?(String)
      end
    end

    @fully_valid_ids = @validation_records.select { |record| LocalEvalArtifact.fully_valid?(record) }
                                             .map { |record| record.fetch("id") }.to_set
    @validation_failure_ids = ids.to_set - @fully_valid_ids
    equal!(expected.fetch(:fully_valid), @fully_valid_ids.size, "fully-valid count")
  end

  def verify_benchmark_records
    @benchmark_records = load_partitioned_records("data/benchmark/records")
    expected = LocalEvalArtifact::EXPECTED
    equal!(expected.fetch(:benchmark_records), @benchmark_records.size, "benchmark record count")
    ids = @benchmark_records.map { |record| record.fetch("id") }
    equal!(ids.size, ids.uniq.size, "unique benchmark IDs")
    equal!(@fully_valid_ids, ids.to_set, "fully-valid/benchmark IDs")

    @benchmark_success_ids = Set.new
    @benchmark_failure_ids = Set.new
    @benchmark_records.each do |record|
      require_partition_match!(record, "data/benchmark/records")
      missing = BENCHMARK_REQUIRED_KEYS - record.keys
      extras = record.keys - (BENCHMARK_REQUIRED_KEYS + ["pipeline_amendment_sha256"])
      raise "benchmark key mismatch for #{record.fetch("id")}: missing=#{missing}, extra=#{extras}" unless missing.empty? && extras.empty?
      equal!(2, record.fetch("schema_version"), "benchmark schema version")
      require_backend!(record)
      equal!("#{record.fetch("batch")}/#{record.fetch("id")}", record.fetch("source_path"), "portable benchmark source path")
      equal!(@configuration_sha256, record.fetch("configuration_sha256"), "benchmark configuration for #{record.fetch("id")}")
      raise "absolute benchmark source path: #{record.fetch("id")}" if record.fetch("source_path").start_with?("/")

      if record.fetch("timing_fixed")
        correction = @corrections_by_id.fetch(record.fetch("id"))
        verify_timing_correction_record(record, correction)
      else
        raise "uncorrected benchmark has correction metadata: #{record.fetch("id")}" unless record.fetch("timing_correction").nil?
      end

      if record.fetch("success")
        @benchmark_success_ids << record.fetch("id")
        equal!(5, record.fetch("metrics").size, "successful metric count for #{record.fetch("id")}")
        equal!(5, record.fetch("wall_seconds").size, "successful wall count for #{record.fetch("id")}")
        equal!(6, record.fetch("executions").size, "successful execution count for #{record.fetch("id")}")
        record.fetch("metrics").each do |metric|
          time = Float(metric.fetch("time"))
          raise "nonpositive/nonfinite metric: #{record.fetch("id")}" unless time.positive? && time.finite?
        end
      else
        @benchmark_failure_ids << record.fetch("id")
        raise "failed benchmark has parsed metrics: #{record.fetch("id")}" unless record.fetch("metrics").empty?
      end
    end

    counts = @release_summary.fetch("counts")
    equal!(counts.fetch("benchmark_successes"), @benchmark_success_ids.size, "benchmark success count")
    equal!(counts.fetch("benchmark_failures"), @benchmark_failure_ids.size, "benchmark failure count")
    timing_fixed_ids = @benchmark_records.select { |record| record.fetch("timing_fixed") }
                                         .map { |record| record.fetch("id") }.to_set
    equal!(@corrections_by_id.keys.to_set, timing_fixed_ids, "timing-corrected benchmark IDs")
  end

  def verify_timing_correction_record(record, correction)
    metadata = record.fetch("timing_correction")
    raise "missing timing-correction metadata: #{record.fetch("id")}" unless metadata.is_a?(Hash)

    equal!(@source_correction_amendment_sha256, metadata.fetch("source_correction_amendment_sha256"), "source-correction digest for #{record.fetch("id")}")
    equal!(correction.fetch("original_issue_categories"), metadata.fetch("issue_categories"), "timing issues for #{record.fetch("id")}")
    equal!(correction.fetch("changed_paths"), metadata.fetch("changed_paths"), "changed paths for #{record.fetch("id")}")
    original = metadata.fetch("original_source")
    corrected = metadata.fetch("corrected_source")
    equal!(correction.dig("original_source", "commit"), original.fetch("commit"), "original commit for #{record.fetch("id")}")
    equal!(correction.dig("original_source", "digest"), original.fetch("digest"), "original digest for #{record.fetch("id")}")
    equal!(correction.fetch("original_source_url"), original.fetch("url"), "original URL for #{record.fetch("id")}")
    equal!(correction.dig("corrected_source", "commit"), corrected.fetch("commit"), "corrected commit for #{record.fetch("id")}")
    equal!(correction.dig("corrected_source", "digest"), corrected.fetch("digest"), "corrected digest for #{record.fetch("id")}")
    equal!(correction.fetch("corrected_source_url"), corrected.fetch("url"), "corrected URL for #{record.fetch("id")}")
    raise "timing correction did not compile: #{record.fetch("id")}" unless metadata.dig("build", "success") == true
  end

  def verify_canonical_benchmark_maps
    full = LocalEvalArtifact.load_yaml(file("data/benchmark/benchmark_full_results.yaml"))
    compatibility = LocalEvalArtifact.load_yaml(file("data/benchmark/benchmark_results.yaml"))
    equal!(LocalEvalArtifact::EXPECTED.fetch(:benchmark_records), full.size, "full benchmark map count")
    equal!(full.keys.sort, compatibility.keys.sort, "benchmark map IDs")
    @benchmark_records.each do |record|
      id = record.fetch("id")
      full_success, metrics = full.fetch(id)
      equal!(record.fetch("success"), full_success, "full benchmark status for #{id}")
      equal!(record.fetch("success"), compatibility.fetch(id), "compatibility benchmark status for #{id}")
      if record.fetch("success")
        equal!(record.fetch("metrics"), metrics, "full benchmark metrics for #{id}")
      end
    end
  end

  def verify_timing_audit_and_corrections
    timing_root = file("data/timing-audit")
    listed = parse_checksum_list(File.join(timing_root, "evidence-files.sha256"), base: timing_root)
    actual = LocalEvalArtifact.regular_files(timing_root).reject do |path|
      path == File.join(timing_root, "evidence-files.sha256")
    end.map { |path| LocalEvalArtifact.relative_path(timing_root, path) }.sort
    equal!(actual, listed.keys.sort, "timing evidence checksum file set")

    decisions = LocalEvalArtifact.read_jsonl(
      file("data/timing-audit/static-audit/final/decisions.jsonl")
    )
    equal!(LocalEvalArtifact::EXPECTED.fetch(:timing_audit_records), decisions.size, "timing audit record count")
    verdict_counts = decisions.each_with_object(Hash.new(0)) do |record, counts|
      counts[record.fetch("final_verdict")] += 1
    end
    equal!({ "invalid" => 587, "valid" => 1_028 }, verdict_counts.sort.to_h, "timing audit verdicts")
    invalid_ids = decisions.select { |record| record.fetch("final_verdict") == "invalid" }
                           .map { |record| record.fetch("program_id") }.to_set
    equal!(@corrections_by_id.keys.to_set, invalid_ids, "timing audit/correction IDs")

    final_corrections = LocalEvalArtifact.read_jsonl(
      file("data/timing-audit/corrections/final/corrections.jsonl")
    )
    equal!(@correction_records, final_corrections, "final/provenance correction records")
    raise "non-accepted final timing correction" unless final_corrections.all? do |record|
      record.fetch("timing_fixed") == true && record.fetch("final_verdict") == "accept"
    end
    final_manifest_path = file("data/timing-audit/corrections/final/manifest.yaml")
    final_manifest = LocalEvalArtifact.load_yaml(final_manifest_path)
    equal!(@source_correction_amendment.fetch("source_evidence_manifest_sha256"), LocalEvalArtifact.sha256(final_manifest_path), "source-correction evidence manifest")
    equal!(LocalEvalArtifact::EXPECTED.fetch(:timing_corrections), final_manifest.fetch("record_count"), "final timing correction count")
    equal!(587, final_manifest.dig("compile_validation", "compile_successes"), "timing correction compile successes")

    proposals = LocalEvalArtifact.read_jsonl(file("data/timing-audit/corrections/proposals/summary-full.jsonl"))
    reviews = LocalEvalArtifact.read_jsonl(file("data/timing-audit/corrections/postfix-review/summary-full.jsonl"))
    adjudications = LocalEvalArtifact.read_jsonl(file("data/timing-audit/corrections/adjudication/summary-full.jsonl"))
    equal!(587, proposals.size, "timing proposal count")
    equal!(587, reviews.size, "post-fix review count")
    equal!(26, adjudications.size, "post-fix adjudication count")
    equal!({ "accept" => 561, "reject" => 26 }, reviews.each_with_object(Hash.new(0)) { |r, h| h[r.fetch("verdict")] += 1 }.sort.to_h, "post-fix review verdicts")
    raise "post-fix adjudication did not accept all records" unless adjudications.all? { |record| record.fetch("final_verdict") == "accept" }

    comparisons = LocalEvalArtifact.read_jsonl(file("data/timing-audit/rerun-comparison.jsonl"))
    equal!(@corrections_by_id.keys.sort, comparisons.map { |record| record.fetch("id") }.sort, "timing rerun comparison IDs")
    benchmarks = @benchmark_records.to_h { |record| [record.fetch("id"), record] }
    comparisons.each do |comparison|
      id = comparison.fetch("id")
      current = benchmarks.fetch(id)
      raise "prior timing-audit measurement was not successful: #{id}" unless comparison.dig("prior", "success") == true
      equal!(current.fetch("success"), comparison.dig("corrected", "success"), "corrected comparison status for #{id}")
      equal!(current.fetch("metrics"), comparison.dig("corrected", "metrics"), "corrected comparison metrics for #{id}")
      equal!(current.fetch("wall_seconds"), comparison.dig("corrected", "wall_seconds"), "corrected comparison walls for #{id}")
      equal!(comparison.dig("prior", "success") != comparison.dig("corrected", "success"), comparison.fetch("success_changed"), "comparison status-change flag for #{id}")
    end

    counts = @release_summary.fetch("counts")
    equal!(comparisons.count { |record| record.dig("corrected", "success") }, counts.fetch("timing_correction_benchmark_successes"), "corrected benchmark successes")
    guard = @release_summary.fetch("localized_rerun_guard")
    raise "localized-rerun guard is not marked unchanged" unless guard.fetch("unchanged") == true
    equal!(guard.fetch("baseline_sha256"), guard.fetch("final_sha256"), "unaffected before/after digest")
    unaffected = @benchmark_records.reject { |record| @corrections_by_id.key?(record.fetch("id")) }
    equal!(benchmark_records_digest(unaffected), guard.fetch("final_sha256"), "unaffected final record digest")
    equal!(unaffected.size, guard.fetch("unaffected_records"), "unaffected record count")

    comparison_summary = @release_summary.fetch("timing_rerun_comparison")
    equal!(comparisons.size, comparison_summary.fetch("records"), "comparison summary record count")
    equal!(LocalEvalArtifact.sha256(file(comparison_summary.fetch("path"))), comparison_summary.fetch("sha256"), "comparison summary digest")

    completion = LocalEvalArtifact.load_yaml(
      file("data/provenance/scoped-measurement-rerun/scoped_measurement_rerun_completion.yaml")
    )
    completion.fetch("records").each do |id, rerun_record|
      benchmark = benchmarks.fetch(id)
      equal!(benchmark.fetch("success"), rerun_record.fetch("success"), "scoped rerun status for #{id}")
      equal!(benchmark.fetch("metrics"), rerun_record.fetch("metrics"), "scoped rerun metrics for #{id}")
      equal!(benchmark.fetch("wall_seconds"), rerun_record.fetch("wall_seconds"), "scoped rerun walls for #{id}")
    end
  end

  def verify_scores
    counts = Hash.new(0)
    @score_rows = 0
    CSV.foreach(file("data/scoring/scored_results.csv"), headers: true) do |row|
      @score_rows += 1
      counts[Integer(row.fetch("overall_score"), 10)] += 1
    end
    equal!(LocalEvalArtifact::EXPECTED.fetch(:score_records), @score_rows, "score record count")
    expected_counts = @release_summary.dig("counts", "score_counts")
    equal!(expected_counts, counts.sort.to_h, "score distribution")

    metadata = LocalEvalArtifact.load_yaml(file("data/scoring/scoring_metadata.yaml"))
    equal!(@score_rows, metadata.fetch("record_count"), "scoring metadata record count")
    equal!(expected_counts, metadata.fetch("score_counts"), "scoring metadata distribution")
    raise "threshold review is not final" unless metadata.fetch("thresholds_reviewed") == true
  end

  def verify_evidence_scope
    validation_evidence_ids = evidence_ids("data/validation/failures")
    benchmark_evidence_ids = evidence_ids("data/benchmark/failures")
    raise "validation evidence exists for successful IDs" unless (validation_evidence_ids - @validation_failure_ids).empty?
    equal!(@benchmark_failure_ids, benchmark_evidence_ids, "benchmark failure evidence IDs")

    reference_directories = Dir.glob(file("data/validation/references/*")).select { |path| File.directory?(path) }
    equal!(11, reference_directories.size, "reference benchmark count")

    attempt_metadata = Dir.glob(file("data/benchmark/attempts/**/benchmark_metadata.yaml"))
    equal!(1, attempt_metadata.size, "archived amended-attempt count")
    raise "wrong archived attempt" unless attempt_metadata.first.include?("spmv_gpt-5.6-terra-low_hybrid_r2")
  end

  def verify_incident
    root = file("data/provenance/incidents/cahn-hilliard-nondeterminism")
    canonical = LocalEvalArtifact.load_yaml(File.join(root, "canonical/source_staging.yaml"))
    replacement = LocalEvalArtifact.load_yaml(File.join(root, "replacement/source_staging.yaml"))
    equal!(canonical.fetch("content_sha256"), replacement.fetch("content_sha256"), "incident source digest")

    canonical_metadata = LocalEvalArtifact.load_yaml(File.join(root, "canonical/validation_metadata.yaml"))
    replacement_metadata = LocalEvalArtifact.load_yaml(File.join(root, "replacement/validation_metadata.yaml"))
    raise "canonical incident record should pass" unless canonical_metadata.fetch("stages").values.all? { |value| value == true }
    raise "replacement incident should fail comparison" unless replacement_metadata.dig("stages", "output_comparison") == false
    require_file("data/provenance/incidents/cahn-hilliard-nondeterminism/README.md")
  end

  def load_partitioned_records(relative_root)
    paths = Dir.glob(file("#{relative_root}/*/*.jsonl")).sort
    equal!(44, paths.size, "#{relative_root} partition count")
    paths.flat_map do |path|
      records = LocalEvalArtifact.read_jsonl(path)
      records.each { |record| record["_partition_path"] = LocalEvalArtifact.relative_path(@root, path) }
      records
    end
  end

  def pipeline_amendment_relatives
    root = file("data/provenance/amendments")
    names = Dir.glob(File.join(root, "pipeline_amendment*.yaml")).map { |path| File.basename(path) }
    names.select! { |name| name == "pipeline_amendment.yaml" || name.match?(/\Apipeline_amendment\.\d+\.yaml\z/) }
    names.sort_by! do |name|
      name == "pipeline_amendment.yaml" ? 1 : Integer(name.match(/\.(\d+)\.yaml\z/)[1], 10)
    end
    raise "no pipeline amendments" if names.empty?

    names.map { |name| "data/provenance/amendments/#{name}" }
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

  def require_partition_match!(record, relative_root)
    partition = record.delete("_partition_path")
    expected = "#{relative_root}/#{record.fetch("benchmark")}/#{record.fetch("backend")}.jsonl"
    equal!(expected, partition, "partition for #{record.fetch("id")}")
  end

  def require_backend!(record)
    raise "invalid backend for #{record.fetch("id")}" unless LocalEvalArtifact::BACKENDS.include?(record.fetch("backend"))
  end

  def evidence_ids(relative_root)
    return Set.new unless File.directory?(file(relative_root))

    Dir.glob(file("#{relative_root}/*/*")).select { |path| File.directory?(path) }
       .map { |path| File.basename(path) }.to_set
  end

  def verify_sidecar(relative)
    path = file(relative)
    sidecar = "#{path}.sha256"
    require_file(relative)
    raise "missing sidecar: #{sidecar}" unless File.file?(sidecar)
    equal!(LocalEvalArtifact.sha256(path), LocalEvalArtifact.parse_sidecar(sidecar), "sidecar for #{relative}")
  end

  def parse_checksum_list(path, base:)
    entries = {}
    File.foreach(path, chomp: true).with_index(1) do |line, line_number|
      match = line.match(/\A([0-9a-f]{64})  (.+)\z/)
      raise "malformed checksum line #{line_number}: #{path}" unless match
      relative = match[2]
      ensure_safe_relative!(relative)
      raise "duplicate checksum entry: #{relative}" if entries.key?(relative)
      target = File.expand_path(relative, base)
      expected_prefix = "#{File.expand_path(base)}/"
      raise "checksum path escapes base: #{relative}" unless target.start_with?(expected_prefix)
      raise "missing checksum target: #{relative}" unless File.file?(target)
      equal!(match[1], LocalEvalArtifact.sha256(target), "checksum list entry #{relative}")
      entries[relative] = match[1]
    end
    entries
  end

  def ensure_safe_relative!(relative)
    pathname = Pathname.new(relative)
    raise "absolute checksum path: #{relative}" if pathname.absolute?
    raise "unsafe checksum path: #{relative}" if pathname.each_filename.any? { |part| part == ".." }
  end

  def subtree_bytes(relative)
    root = file(relative)
    return 0 unless File.directory?(root)

    LocalEvalArtifact.regular_files(root).sum { |path| File.size(path) }
  end

  def require_file(relative)
    path = file(relative)
    raise "missing file: #{relative}" unless File.file?(path)
    path
  end

  def equal!(expected, actual, label)
    raise "#{label} mismatch: expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
  end

  def file(relative)
    candidate = File.expand_path(relative, @root)
    prefix = "#{@root}/"
    raise "unsafe repository path: #{relative}" unless candidate.start_with?(prefix)
    candidate
  end
end

options = { root: File.expand_path("..", __dir__) }
OptionParser.new do |opts|
  opts.banner = "Usage: ruby tools/verify_release.rb [--root=PATH]"
  opts.on("--root=PATH", "Repository root") { |value| options[:root] = value }
end.parse!

ReleaseVerifier.new(options.fetch(:root)).run
