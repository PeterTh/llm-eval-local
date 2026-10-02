# frozen_string_literal: true

require_relative "timing_audit"
require_relative "../../../lib/local_evaluation"

module QtclusteringBoundary
  STAGES = %w[basic_para validation_build validation_run internal_validation output_comparison].freeze
  BACKENDS = %w[omp cuda mpi hybrid].freeze
  PRIMARY_MODEL = "gpt-5.6-luna"
  ADJUDICATION_MODEL = "gpt-6.1-sol"
  PILOT_CONTROLS = %w[
    qtclustering_gpt-6-luna-medium_hybrid_r2
    qtclustering_gpt-6-luna-medium_hybrid_r4
    qtclustering_claude-sonnet-5-cc-medium_hybrid_r2
    qtclustering_gpt-5.6-sol-xhigh_hybrid_r2
  ].freeze

  module_function

  def identity(benchmark, model, backend, run)
    "#{benchmark}_#{model}_#{backend}_r#{Integer(run)}"
  end

  def passed?(stages)
    values = STAGES.map { |key| stages.fetch(key) }
    raise "Invalid validation stage sequence" unless values.all? { |v| v == true || v == false } &&
      values.each_cons(2).none? { |a, b| !a && b }
    values.all?
  end

  class Builder
    def initialize(release_root:, validation_runs:, source_root:, source_commit:,
                   reference_root:, reference_commit:, benchmark_config:, context_path:, output_dir:, trial_size: 16)
      @release = File.realpath(release_root)
      @validations = validation_runs.map { |path| File.realpath(path) }
      @source = TimingAudit::SourceRepository.new(root: source_root, commit: source_commit)
      @reference_root = File.realpath(reference_root)
      @reference_commit = reference_commit
      @config_path = File.realpath(benchmark_config)
      @context_path = File.realpath(context_path)
      @output = File.expand_path(output_dir)
      @trial_size = Integer(trial_size)
      raise "Invalid trial size" unless @trial_size.positive?
      @inputs = []
      @excluded = []
    end

    def run
      raise "Output already exists: #{@output}" if File.exist?(@output)
      records = release_records + @validations.flat_map { |path| validation_records(path) }
      records.sort_by! { |row| row.fetch("id") }
      raise "Empty or duplicate inventory" if records.empty? || records.map { |r| r.fetch("id") }.uniq.size != records.size
      records.each do |record|
        record.merge!(@source.source_record(record.fetch("source_prefix")))
        expected_tree = TimingAudit.capture!("git", "-C", @source.root, "rev-parse",
          "#{record.fetch('evaluated_source_commit')}:#{record.fetch('source_prefix')}").strip
        raise "Evaluated source changed for #{record.fetch('id')}" unless expected_tree == record.fetch("source_tree_oid")
      end
      reference = TimingAudit.capture!("git", "-C", @reference_root, "show",
        "#{@reference_commit}:qtclustering/qtclustering.cpp")
      reference_metadata = { "commit" => @reference_commit, "path" => "qtclustering/qtclustering.cpp",
        "sha256" => TimingAudit.sha256_bytes(reference) }
      catalog_path = File.join(@release, "release/catalog.json")
      config_paths = [@config_path] + JSON.parse(File.read(catalog_path)).fetch("campaigns").map do |campaign|
        File.join(@release, campaign.fetch("benchmark_config"))
      end
      configurations = config_paths.uniq.map do |path|
        config = YAML.safe_load_file(path, aliases: true)
        settings = config.fetch("cells").transform_values { |benchmarks| benchmarks.fetch("qtclustering").slice("args", "timeout_seconds") }
        @inputs << file_evidence(path)
        settings
      end
      raise "QT-clustering configurations differ between campaigns" unless configurations.uniq.size == 1
      context = File.read(@context_path)
      @inputs << file_evidence(@context_path)
      numbered = reference.lines.each_with_index.map { |line, i| format("%6d | %s", i + 1, line) }.join
      appendix = "Pinned sequential reference #{JSON.generate(reference_metadata)}\n#{numbered}\n" \
        "Inherited QT-clustering benchmark settings (all release campaigns agree):\n#{JSON.pretty_generate(configurations.first)}\n\n#{context}"
      prompt_path = File.expand_path("../prompts/qtclustering_boundary_prompt.txt", __dir__)
      prompt = File.read(prompt_path).sub("__REFERENCE_CONTEXT__") { appendix.gsub("%", "%%") }
      schema = JSON.parse(File.read(File.expand_path("../schemas/timing_audit_schema.json", __dir__)))
      schema.fetch("properties").fetch("evidence").fetch("items").fetch("properties").fetch("lines")["pattern"] = "^[1-9][0-9]*(-[1-9][0-9]*)?$"
      trial = pilot_ids(records)
      artifacts = {
        "prompt-template.txt" => prompt,
        "result-schema.json" => JSON.pretty_generate(schema) + "\n",
        "runner-snapshot.rb" => File.read(File.expand_path("timing_audit.rb", __dir__)),
        "preparer-snapshot.rb" => File.read(__FILE__),
        "reference-source.txt" => reference,
        "platform-context.txt" => context,
        "inputs.jsonl" => TimingAudit.dump_jsonl(@inputs.uniq),
        "excluded.jsonl" => TimingAudit.dump_jsonl(@excluded),
        "inventory.jsonl" => TimingAudit.dump_jsonl(records),
        "trial-ids.txt" => trial.join("\n") + "\n"
      }
      artifacts.each { |name, bytes| TimingAudit.atomic_write(File.join(@output, name), bytes) }
      manifest = {
        "schema_version" => 1, "inventory_version" => 1, "created_at" => TimingAudit.utc_now,
        "release_root" => @release, "dataset_path" => File.join(@release, "release/scored_results.csv"),
        "dataset_sha256" => TimingAudit.sha256_file(File.join(@release, "release/scored_results.csv")),
        "selection" => { "basis" => "qtclustering_validation_boundary_review", "benchmark" => "qtclustering",
          "parallelization_types" => BACKENDS, "validation_status" => 5, "benchmark_success" => nil,
          "records" => records.size, "by_origin" => records.group_by { |r| r.fetch("origin") }.transform_values(&:size),
          "by_backend" => records.group_by { |r| r.fetch("par_type") }.transform_values(&:size) },
        "generated_source" => { "root" => @source.root, "commit" => @source.commit,
          "repository" => "https://github.com/PeterTh/llm-eval-generated" },
        "reference_source" => reference_metadata,
        "contract" => "include all input-dependent clustering computation; complete per-thread/device/rank timing",
        "review_models" => { "primary" => PRIMARY_MODEL, "primary_effort" => "high",
          "adjudication" => ADJUDICATION_MODEL, "adjudication_effort" => "xhigh" },
        "trial" => { "size" => trial.size, "ids" => trial },
        "artifacts" => { "prompt_template_sha256" => TimingAudit.sha256_bytes(prompt),
          "result_schema_sha256" => TimingAudit.sha256_bytes(artifacts.fetch("result-schema.json")),
          "runner_sha256" => TimingAudit.sha256_bytes(artifacts.fetch("runner-snapshot.rb")),
          "inventory_sha256" => TimingAudit.sha256_bytes(artifacts.fetch("inventory.jsonl")),
          "trial_ids_sha256" => TimingAudit.sha256_bytes(artifacts.fetch("trial-ids.txt")) },
        "retained_artifacts" => artifacts.transform_values { |bytes| TimingAudit.sha256_bytes(bytes) }
      }
      TimingAudit.atomic_write(File.join(@output, "manifest.yaml"), YAML.dump(manifest))
      puts JSON.pretty_generate(manifest.slice("selection", "trial", "review_models"))
      manifest
    end

    private

    def file_evidence(path)
      { "path" => File.realpath(path), "sha256" => TimingAudit.sha256_file(path) }
    end

    def base_record(id:, model:, backend:, run:, batch:, commit:, origin:)
      raise "Unknown backend #{backend}" unless BACKENDS.include?(backend)
      raise "Identity mismatch #{id}" unless id == QtclusteringBoundary.identity("qtclustering", model, backend, run)
      raise "Unpinned source" unless commit.match?(/\A[0-9a-f]{40}\z/)
      { "id" => id, "benchmark" => "qtclustering", "model" => model, "par_type" => backend,
        "run" => Integer(run), "source_batch" => batch, "source_prefix" => "#{batch}/#{id}",
        "evaluated_source_commit" => commit, "origin" => origin, "metric_label" => "Clustering time",
        "benchmark_median_time_ms" => nil, "overall_score" => nil, "benchmark_config_sha256" => nil }
    end

    def release_records
      catalog_path = File.join(@release, "release/catalog.json")
      csv_path = File.join(@release, "release/scored_results.csv")
      @inputs.concat([file_evidence(catalog_path), file_evidence(csv_path)])
      validation = {}
      JSON.parse(File.read(catalog_path)).fetch("campaigns").each do |campaign|
        paths = Dir[File.join(@release, campaign.fetch("validation_records"))].sort
        raise "No validation evidence for campaign" if paths.empty?
        paths.each do |path|
          @inputs << file_evidence(path)
          TimingAudit.load_jsonl(path).each do |record|
            next unless (record["benchmark"] || record.dig("metadata", "benchmark")) == "qtclustering"
            id = record.fetch("id")
            raise "Duplicate release validation #{id}" if validation.key?(id)
            validation[id] = [record, campaign]
          end
        end
      end
      selected = []
      seen = []
      CSV.foreach(csv_path, headers: true) do |row|
        next unless row.fetch("benchmark") == "qtclustering"
        id = QtclusteringBoundary.identity("qtclustering", row.fetch("model"), row.fetch("par_type"), row.fetch("run"))
        raise "Duplicate release row #{id}" if seen.include?(id)
        seen << id
        record, campaign = validation.fetch(id)
        passed = QtclusteringBoundary.passed?(record["stages"] || record.fetch("metadata").fetch("stages"))
        raise "CSV disagrees with validation #{id}" unless passed == (row.fetch("validation_status") == "5")
        unless passed
          @excluded << { "program_id" => id, "reason" => "validation_failed", "origin" => "release" }
          next
        end
        corrected = row.fetch("timing_fixed") == "true"
        commit = corrected ? row.fetch("corrected_source_commit") : campaign.fetch("source_commit")
        selected << base_record(id: id, model: row.fetch("model"), backend: row.fetch("par_type"),
          run: row.fetch("run"), batch: row.fetch("source_batch"), commit: commit, origin: "release").merge(
            "previously_timing_fixed" => corrected, "previous_benchmark_success" => row.fetch("benchmark_success") == "true")
      end
      raise "Release coverage mismatch" unless seen.sort == validation.keys.sort
      selected
    end

    def validation_records(root)
      manifest = LocalEvaluation::Manifest.new(root)
      source = manifest.data.fetch("experiment_repository")
      raise "Unpinned validation source" unless source["git"] && !source["dirty"]
      path = File.join(root, "validation/all_validation_results.yaml")
      results = LocalEvaluation.load_yaml(path, permitted_classes: [ValidationResult])
      @inputs.concat([file_evidence(manifest.path), file_evidence(path)])
      ids = results.map(&:id_string)
      raise "Incomplete or duplicate validation" unless ids.uniq == ids && ids.sort == manifest.runs.keys.sort
      results.filter_map do |result|
        info = manifest.runs.fetch(result.id_string)
        next unless info.fetch("benchmark") == "qtclustering"
        raise "Validation identity mismatch" unless result.is_for(info.fetch("benchmark"), info.fetch("model"), info.fetch("par_type"), info.fetch("run"))
        metadata_path = File.join(root, "validation", result.id_string, "validation_metadata.yaml")
        metadata = LocalEvaluation.load_yaml(metadata_path)
        @inputs << file_evidence(metadata_path)
        stages = STAGES.to_h { |key| [key, result.public_send(key)] }
        raise "Validation metadata mismatch" unless metadata.fetch("id") == result.id_string &&
          metadata.fetch("manifest_sha256") == TimingAudit.sha256_file(manifest.path) && metadata.fetch("stages") == stages
        unless QtclusteringBoundary.passed?(stages)
          @excluded << { "program_id" => result.id_string, "reason" => "validation_failed", "origin" => root }
          next
        end
        base_record(id: result.id_string, model: result.model, backend: result.par_type,
          run: result.run, batch: info.fetch("batch"), commit: source.fetch("commit"), origin: root).merge(
            "previously_timing_fixed" => false, "previous_benchmark_success" => nil)
      end
    end

    def pilot_ids(records)
      selected = PILOT_CONTROLS.filter_map { |id| records.find { |r| r.fetch("id") == id } }.first(@trial_size)
      while selected.size < [@trial_size, records.size].min
        selected << (records - selected).min_by do |record|
          [selected.count { |r| r.fetch("par_type") == record.fetch("par_type") },
           selected.count { |r| r.fetch("source_batch") == record.fetch("source_batch") },
           selected.count { |r| r.fetch("model") == record.fetch("model") },
           TimingAudit.sha256_bytes(record.fetch("id"))]
        end
      end
      selected.map { |r| r.fetch("id") }
    end
  end
end
