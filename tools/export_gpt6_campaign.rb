#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only import of the completed GPT-6 + historical QT campaign. No evaluated
# program, validation, benchmark, or model invocation is executed by this tool.
require_relative "artifact_common"
require "open3"
require "optparse"

class GPT6CampaignExport
  include LocalEvalArtifact
  BATCH = "20260929-135931"
  SHARED = "corrections/20261001-gpt6-qt"
  ORIGINAL = "32f1becd283322d1edff43dd47a3b3bc8e2cdad6"
  CORRECTED = "3a47d7cba6624f4bdfe004fba3383b5e3c62e93f"
  COMPLETED = "2026-10-02T01:03:56Z"

  def initialize(root:, experiment:, home:, resume: false)
    @root, @experiment, @home = [root, experiment, home].map { |p| File.expand_path(p) }
    @resume = resume
    require File.join(@experiment, "tools/timing_audit/bin/export_benchmark_batch")
    @native = File.join(@home, "llm_para_local_evaluation/20261001-gpt6-validation")
    @corrected = File.join(@home, "llm_para_local_evaluation/20261001-gpt6-qt-corrected")
    @campaign = File.join(@home, "llm_para_campaigns/#{BATCH}-gpt6-medium")
    @final = File.join(@home, "llm_timing_fixes/20261001-gpt6-qt-final")
    @registry = LocalEvalArtifact.read_jsonl(File.join(@final, "corrections.jsonl"))
    @by_id = @registry.to_h { |r| [r.fetch("program_id"), r] }
    @method_by_digest = LocalEvalArtifact.regular_files(@root).select { |p| p.include?("/method/") }
      .to_h { |p| [sha256(p), LocalEvalArtifact.relative_path(@root, p)] }
  end

  def write(relative, content)
    destination = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(destination))
    File.binwrite(destination, content)
  end

  def json(relative, value)
    write(relative, JSON.pretty_generate(value) + "\n")
  end

  def jsonl(relative, values)
    write(relative, values.map { |v| JSON.generate(v) + "\n" }.join)
  end

  def copy(source, relative)
    write(relative, File.binread(source))
  end

  def copy_selected(source, destination, names)
    names.each do |name|
      file = File.join(source, name)
      copy(file, "#{destination}/#{name}") if File.file?(file)
    end
  end

  def partition(relative, records)
    records.group_by { |r| [r["benchmark"] || r.dig("metadata", "benchmark"), r["backend"] || r.dig("metadata", "par_type")] }
      .sort.each { |(benchmark, backend), rs| jsonl("#{relative}/#{benchmark}/#{backend}.jsonl", rs.sort_by { |r| r.fetch("id") }) }
  end

  def retain_method(content, name)
    digest = Digest::SHA256.hexdigest(content)
    @method_by_digest[digest] ||= begin
      relative = "method/20261001-gpt6/#{digest[0, 12]}-#{File.basename(name)}"
      write(relative, content)
      relative
    end
  end

  def pipeline_layout(pipeline)
    pipeline.fetch("files").to_h do |relative, digest|
      unless @method_by_digest[digest]
        candidate = File.join(pipeline.fetch("root"), relative)
        content = File.binread(candidate) if File.file?(candidate) && sha256(candidate) == digest
        unless content
          # The live scratch checkout may have advanced under an amendment. Find
          # the exact previously pinned blob; never substitute the current file.
          commits, status = Open3.capture2("git", "-C", @experiment, "log", "--format=%H", "--", relative)
          raise "Cannot locate method history #{relative}" unless status.success?
          commits.lines.map(&:strip).each do |commit|
            bytes, found = Open3.capture2("git", "-C", @experiment, "show", "#{commit}:#{relative}")
            if found.success? && Digest::SHA256.hexdigest(bytes) == digest
              content = bytes
              break
            end
          end
        end
        raise "Pinned method unavailable #{relative}: #{digest}" unless content
        retain_method(content, relative)
      end
      [relative, @method_by_digest.fetch(digest)]
    end
  end

  def validation(native, destination)
    manifest = LocalEvaluation::Manifest.new(native)
    digest = sha256(manifest.path)
    prior = File.join(@root, destination, "provenance/evaluation_manifest.yaml")
    raise "Refusing to replace another validation export" if File.file?(prior) && sha256(prior) != digest
    results = LocalEvaluation.load_yaml(File.join(native, "validation/all_validation_results.yaml"), permitted_classes: [ValidationResult])
    raise "Validation scope differs" unless results.map(&:id_string).sort == manifest.runs.keys.sort
    copy_selected(native, "#{destination}/provenance", %w[evaluation_manifest.yaml evaluation_manifest.yaml.sha256 preflight.yaml campaign.json])
    copy_selected(File.join(native, "validation"), "#{destination}/validation", %w[all_validation_results.yaml preflight.yaml])
    records = results.sort_by(&:id_string).map do |result|
      id = result.id_string
      info = manifest.runs.fetch(id)
      directory = File.join(native, "validation", id)
      metadata_path = File.join(directory, "validation_metadata.yaml")
      metadata = LocalEvaluation.load_yaml(metadata_path)
      raise "Validation manifest differs #{id}" unless metadata.fetch("manifest_sha256") == digest
      raise "Validation outcome differs #{id}" unless LocalEvalArtifact::VALIDATION_STAGES.all? { |s| metadata.fetch("stages").fetch(s) == result.public_send(s) }
      logs = Dir[File.join(directory, "{cmake,build,validation_out}_*.log")].sort.to_h { |p| [File.basename(p), sha256(p)] }
      retained = logs.keys.select { |n| n.start_with?("validation_out_") || !result.validation_build || n.end_with?("_command.log", "_wall_time.log", "_exitcode.log") }
      { "id" => id, "source_batch" => info.fetch("batch"), "source_commit" => manifest.data.dig("experiment_repository", "commit"),
        "metadata" => metadata, "metadata_sha256" => sha256(metadata_path),
        "result" => File.read(File.join(directory, "validation_result.txt")),
        "source_staging" => File.file?(File.join(directory, "source_staging.yaml")) ? LocalEvaluation.load_yaml(File.join(directory, "source_staging.yaml")) : nil,
        "log_sha256" => logs, "logs" => retained.to_h { |n| [n, File.read(File.join(directory, n))] } }
    end
    partition("#{destination}/validation/records", records)
    # Interrupted attempts are observations, not completed failures or retries.
    attempts = Dir[File.join(native, "validation/attempts/*/*/{*.log,validation_metadata.yaml,validation_result.txt,source_staging.yaml}")].select { |p| File.file?(p) }
    attempts.each { |p| copy(p, "#{destination}/validation/attempts/#{p.delete_prefix(File.join(native, 'validation/attempts') + '/')}") }
    Dir[File.join(native, "validation/reference/*/{*.log,reference_metadata.yaml}")].sort.each do |p|
      copy(p, "#{destination}/validation/references/#{File.basename(File.dirname(p))}/#{File.basename(p)}")
    end
    json("#{destination}/method/layout.json", pipeline_layout(manifest.data.fetch("pipeline_source")))
    records
  end

  def benchmarks(native, destination, expected_ids)
    manifest = LocalEvaluation::Manifest.new(native)
    full = BenchmarkValidationBatch.full_results(native)
    raise "Unexpected benchmark scope" unless full.keys.sort == expected_ids.sort
    guard = BenchmarkValidationBatch.verify_partition!(native, expected_ids.sort)
    records, evidence, failures = [], [], []
    full.keys.sort.each do |id|
      directory = File.join(native, "benchmark", id)
      metadata_path = File.join(directory, "benchmark_metadata.yaml")
      metadata = LocalEvaluation.load_yaml(metadata_path)
      record = BenchmarkBatchExport.record(id, metadata, @by_id[id])
      reconstructed = BenchmarkBatchExport.native_metadata(record, manifest.runs.fetch(id), metadata.keys)
      raise "Native benchmark reconstruction differs #{id}" unless YAML.dump(reconstructed) == File.read(metadata_path)
      names = Dir.children(directory).select { |n| BenchmarkBatchExport::LOG_PATTERN.match?(n) }.sort
      evidence << { "id" => id, "metadata_sha256" => sha256(metadata_path), "metadata_key_order" => metadata.keys,
                    "log_sha256" => names.to_h { |n| [n, sha256(File.join(directory, n))] } }
      unless metadata.fetch("success")
        stderr = names.grep(/stderr/).map { |n| File.read(File.join(directory, n)) }.join("\n")
        failures << { "id" => id, "category" => BenchmarkBatchExport.failure_category(metadata, stderr), "timing_fixed" => record.fetch("timing_fixed") }
        names.each { |n| copy(File.join(directory, n), "#{destination}/failures/#{id}/#{n}") }
      end
      records << record
    end
    partition("#{destination}/records", records)
    jsonl("#{destination}/evidence-index.jsonl", evidence)
    jsonl("#{destination}/failures.jsonl", failures)
    json("#{destination}/summary.json", { "completed_at" => COMPLETED, "records" => records.size, "successful" => records.count { |r| r.fetch("success") },
      "failed" => failures.size, "timing_fixed" => records.count { |r| r.fetch("timing_fixed") }, "warmups" => 1, "measurements" => 5, "retries" => 0,
      "failure_categories" => failures.group_by { |r| r.fetch("category") }.transform_values(&:size), "native_guard" => guard })
    copy_selected(File.join(native, "benchmark"), destination, %w[benchmark_full_results.yaml benchmark_results.yaml benchmark_run_metadata.yaml preflight.yaml])
    copy_selected(native, "#{destination}/provenance", %w[benchmark_config.yaml benchmark_config.yaml.sha256 benchmark_seed.yaml benchmark_seed.yaml.sha256
      source_correction_amendment.yaml source_correction_amendment.yaml.sha256 source_correction_evidence_manifest.yaml source_correction_evidence_manifest.yaml.sha256
      source_correction_ids.txt source_correction_ids.txt.sha256 source_correction_records.jsonl.sha256 pipeline_amendment.yaml pipeline_amendment.yaml.sha256])
    if File.file?(File.join(native, "pipeline_amendment.yaml"))
      amended = LocalEvaluation.load_yaml(File.join(native, "pipeline_amendment.yaml")).fetch("amended_pipeline_source")
      json("#{destination}/method/pipeline-layout.json", pipeline_layout(amended))
    end
    records
  end

  def audit(native, destination)
    inventory = LocalEvalArtifact.read_jsonl(File.join(native, "inventory.jsonl"))
    records = Dir[File.join(native, "results/*.json")].sort.map { |p| JSON.parse(File.read(p)) }
    raise "Audit IDs outside inventory" unless (records.map { |r| r.fetch("program_id") } - inventory.map { |r| r.fetch("id") }).empty?
    copy_selected(native, destination, %w[manifest.yaml inventory.jsonl excluded.jsonl inputs.jsonl trial-ids.txt priority-selection.jsonl priority-ids.txt
      comparison.jsonl comparison.csv summary-full.csv summary-full.jsonl pilot-review.json review-guidance.txt platform-context.txt operational-provenance.json
      prompt-template.txt result-schema.json runner-snapshot.rb static-evidence-snapshot.rb preparer-snapshot.rb])
    jsonl("#{destination}/results.jsonl", records)
    attempts = Dir[File.join(native, "logs/*/attempt-*/metadata.yaml")].sort.map { |p| LocalEvalArtifact.load_yaml(p) }
    jsonl("#{destination}/attempts.jsonl", attempts)
    Dir[File.join(native, "final/*")].sort.each { |p| copy(p, "#{destination}/final/#{File.basename(p)}") if File.file?(p) }
  end

  def corrections
    registry_manifest = LocalEvalArtifact.load_yaml(File.join(@final, "manifest.yaml"))
    raise "Correction registry digest differs" unless sha256(File.join(@final, "corrections.jsonl")) == registry_manifest.dig("artifacts", "corrections_jsonl_sha256")
    raise "Correction scope differs" unless @registry.size == 81 && @by_id.size == 81 && @registry.all? { |r| r.fetch("final_verdict") == "accept" && r.fetch("timing_fixed") }
    %w[proposals review adjudication].each do |label|
      native = File.join(@home, "llm_timing_fixes/20261001-gpt6-qt-#{label}")
      stored = { "proposals" => "proposals", "review" => "postfix-review", "adjudication" => "adjudication" }.fetch(label)
      destination = "#{SHARED}/#{stored}"
      copy_selected(native, destination, %w[manifest.yaml inventory.jsonl trial-ids.txt prompt-template.txt proposal-schema.json result-schema.json runner-snapshot.rb
        static-evidence-snapshot.rb summary-trial.jsonl summary-full.jsonl summary-full.csv platform-context.txt environment-evidence.yaml pilot-review.json])
      inventory = LocalEvalArtifact.read_jsonl(File.join(native, "inventory.jsonl"))
      records = inventory.map do |r|
        id = r.fetch("id")
        file = File.join(native, label == "proposals" ? "proposals" : "results", "#{id}.json")
        key = { "proposals" => "proposal", "review" => "postfix_review", "adjudication" => "adjudication" }.fetch(label)
        raise "#{label} evidence differs #{id}" unless @by_id.fetch(id).fetch(key).fetch("sha256") == sha256(file)
        JSON.parse(File.read(file))
      end
      jsonl("#{destination}/results.jsonl", records)
      jsonl("#{destination}/attempts.jsonl", Dir[File.join(native, "logs/*/attempt-*/metadata.yaml")].sort.map { |p| LocalEvalArtifact.load_yaml(p) })
      if label == "proposals"
        compiles = Dir[File.join(native, "compile/*/*/metadata.yaml")].sort.map do |p|
          record = LocalEvalArtifact.load_yaml(p)
          record["scope"] = File.basename(File.dirname(File.dirname(p)))
          logs = Dir[File.join(File.dirname(p), "*.log")].sort
          record["log_sha256"] = logs.to_h { |f| [File.basename(f), sha256(f)] }
          record["failure_logs"] = logs.to_h { |f| [File.basename(f), File.read(f)] } unless record.fetch("success")
          record
        end
        jsonl("#{SHARED}/materialization/compile-records.jsonl", compiles)
        copy_selected(File.join(native, "materialized"), "#{SHARED}/materialization", %w[summary-trial.yaml summary-full.yaml])
        # Preserve superseded proposal/review evidence, not repeated live prompts/events.
        Dir[File.join(native, "revisions/**/*")].sort.each do |p|
          next unless File.file?(p) && !%w[events.jsonl prompt.txt].include?(File.basename(p))
          copy(p, "#{destination}/revisions/#{p.delete_prefix(File.join(native, 'revisions') + '/')}")
        end
      end
    end
    copy_selected(@final, "#{SHARED}/final", %w[manifest.yaml correction-ids.txt corrections.jsonl campaign.json validation-failures.json
      revalidation-numerical-comparison.json revalidation-numerical-comparison-checker.rb benchmark-exclusion-tooling-verification.json])
    Dir[File.join(@final, "unexpected-validation/**/*.json")].sort.each { |p| copy(p, "#{SHARED}/final/#{p.delete_prefix(@final + '/')}") }
  end

  def aggregate(validations, benchmarks)
    manifest = LocalEvaluation::Manifest.new(@native)
    worker = LocalEvaluation::AggregatePipeline.new(run_dir: @native,
      codex_usage_path: File.join(@root, "metadata/codex-usage/#{BATCH}.jsonl"))
    validation_results = worker.send(:load_validation)
    corrected_results = LocalEvaluation.load_yaml(File.join(@corrected, "validation/all_validation_results.yaml"), permitted_classes: [ValidationResult])
    corrected_results.each { |r| validation_results[r.id_string] = r if manifest.runs.key?(r.id_string) }
    benchmark_results = worker.send(:load_benchmarks)
    results = manifest.runs.sort.to_h do |id, info|
      [id, worker.send(:aggregate_one, id, info, validation_results.fetch(id), benchmark_results[id])]
    end
    # Reuse the exact native CSV serialization in an isolated output directory.
    # No native campaign file is written or refreshed.
    destination = File.join(@root, "batches/#{BATCH}/aggregate")
    worker.instance_variable_set(:@run_dir, destination)
    worker.send(:write_outputs, results)
    FileUtils.rm(File.join(destination, "aggregate_results.yaml")) # reproducible duplicate just generated above
    json("batches/#{BATCH}/aggregate/export.json", {
      "schema_version" => 2, "records" => results.size, "raw_validation_passed" => validations.count { |r| r.dig("metadata", "stages", "output_comparison") },
      "effective_validation_passed" => results.values.count { |r| r.validation_status == 5 }, "benchmark_records" => benchmarks.size,
      "csv_sha256" => sha256(File.join(destination, "aggregate_results.csv")),
      "native_original_validation_sha256" => sha256(File.join(@native, "validation/all_validation_results.yaml")),
      "native_corrected_validation_sha256" => sha256(File.join(@corrected, "validation/all_validation_results.yaml")),
      "codex_usage_sha256" => sha256(File.join(@root, "metadata/codex-usage/#{BATCH}.jsonl")),
      "pipeline_tooling_commit" => "d86f98f9aa7777a7afa66310fe4dce0d83a67dfb",
      "method" => "Native aggregate_one and CSV serialization; the explicit corrected validation observations supersede original observations. No measurements or native files modified." })
    write("batches/#{BATCH}/aggregate/parse-warnings.yaml", YAML.dump(worker.instance_variable_get(:@warnings)))
  end

  def run
    batch = "batches/#{BATCH}"
    [batch, SHARED].each { |p| raise "Refusing to overwrite #{p} (use --resume only for this import's partial output)" if File.exist?(File.join(@root, p)) && !@resume }
    original = validation(@native, batch)
    corrected = validation(@corrected, "#{SHARED}/revalidation")
    failures = JSON.parse(File.read(File.join(@final, "validation-failures.json"))).fetch("records").map { |r| r.fetch("program_id") }.sort
    effective = original.to_h { |r| [r.fetch("id"), r] }
    corrected.each { |r| effective[r.fetch("id")] = r if effective.key?(r.fetch("id")) }
    eligible = effective.values.select { |r| LocalEvalArtifact::VALIDATION_STAGES.all? { |s| r.dig("metadata", "stages", s) == true } }.map { |r| r.fetch("id") }
    raise "Effective GPT-6 validation differs" unless original.size == 660 && eligible.size == 609 && (failures & eligible).empty?
    new_records = benchmarks(@native, "#{batch}/benchmark", eligible)
    historical_ids = @registry.reject { |r| r.fetch("source_batch") == BATCH }.map { |r| r.fetch("program_id") }
    raise "Historical scope differs" unless historical_ids.size == 32 && historical_ids.all? { |id| id.start_with?("qtclustering_") }
    historical_records = benchmarks(@corrected, "#{SHARED}/benchmark", historical_ids)
    corrections
    { "20261001-gpt6" => "#{batch}/timing-audit/primary", "20261001-gpt6-priority" => "#{batch}/timing-audit/priority",
      "20261001-gpt6-adjudication" => "#{batch}/timing-audit/adjudication", "20261001-qtclustering-boundary" => "#{SHARED}/timing-audit/primary",
      "20261001-qtclustering-boundary-sol61" => "#{SHARED}/timing-audit/adjudication" }.each do |name, destination|
      audit(File.join(@home, "llm_timing_audit", name), destination)
    end
    copy_selected(@campaign, "#{SHARED}/completion", %w[benchmark-completion-review.json verify-benchmark-completion.rb benchmark-canary-gate.json benchmark-progress.yaml
      benchmark-driver.rb prepare-historical-qt-benchmark.rb local-evaluation-driver.rb])
    copy_selected(@campaign, "#{batch}/generation", %w[campaign.json model-preflight.json controller.rb run-ids.txt campaign.prelaunch-argument-error.json])
    copy_selected(File.join(@campaign, "method"), "#{batch}/generation/method", %w[experiment.rb general.rb eval_user_support.rb])
    copy_selected(@native, "#{batch}/provenance", %w[validation-triage.json timing-platform-context.txt timing-boundary-question.json])
    Dir[File.join(@native, "benchmark-campaign/**/*")].sort.each do |p|
      next unless File.file?(p) && File.basename(p) != "corrections.jsonl"
      copy(p, "#{batch}/benchmark/campaign/#{p.delete_prefix(File.join(@native, 'benchmark-campaign') + '/')}")
    end
    plan_root = File.join(@corrected, "historical-benchmark-campaign")
    Dir[File.join(plan_root, "**/*")].sort.each do |p|
      next unless File.file?(p) && File.basename(p) != "corrections.jsonl"
      copy(p, "#{SHARED}/benchmark/campaign/#{p.delete_prefix(plan_root + '/')}")
    end
    aggregate(original, new_records)
    json("#{batch}/summary.json", { "schema_version" => 2, "completed_at" => COMPLETED, "validation_records" => 660,
      "raw_validation_passed" => 611, "validation_passed" => 609, "validation_failed" => 51, "benchmarked" => 609,
      "benchmark_successful" => 588, "timing_corrections" => 49, "failed_revalidations" => failures, "shared_corrections" => SHARED })
    json("#{SHARED}/summary.json", { "schema_version" => 1, "completed_at" => COMPLETED, "corrections" => 81,
      "new_gpt6" => 49, "historical_qt" => 32, "revalidation_passed" => 79, "revalidation_failed" => 2,
      "historical_benchmarked" => historical_records.size, "historical_successful" => historical_records.count { |r| r.fetch("success") } })
    [batch, SHARED].each { |p| write("#{p}/checksums.sha256", "") }
    puts "Exported GPT-6 (660 validations, 609 benchmarks) and shared corrections (81 validations, 32 historical benchmarks)."
  end
end

if $PROGRAM_NAME == __FILE__
  options = { root: File.expand_path("..", __dir__), experiment: "/home/petert/llm_eval/experiment", home: "/home/petert" }
  OptionParser.new do |p|
    p.on("--root=PATH") { |v| options[:root] = v }
    p.on("--experiment=PATH") { |v| options[:experiment] = v }
    p.on("--evidence-home=PATH") { |v| options[:home] = v }
    p.on("--resume") { options[:resume] = true }
  end.parse!
  GPT6CampaignExport.new(**options).run
end
