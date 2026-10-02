# frozen_string_literal: true

# Campaign-specific orchestration only; all measurements use the pinned pipeline.
$stdout.sync = true
require "/tmp/gpt6-evaluation-20261001.rhp9wY/experiment/tools/timing_audit/bin/benchmark_validation_batch"

run_dir = "/home/petert/llm_para_local_evaluation/20261001-gpt6-qt-corrected"
final_root = "/home/petert/llm_timing_fixes/20261001-gpt6-qt-final"
baseline_path = "/home/petert/llm_para_local_evaluation/20260819-003427/benchmark_config.yaml"
plan_root = File.join(run_dir, "historical-benchmark-campaign")
raise "Historical benchmark preparation already exists" if File.exist?(plan_root)
run_lock = LocalEvaluation::RunLock.new(run_dir)
host_lock = LocalEvaluation::HostPerformanceLock.new
begin
  manifest = LocalEvaluation::Manifest.new(run_dir)
  manifest.verify_input_revisions!(operation: "preflight")
  LocalEvaluation::Resources.new.verify_topology!
  results = BenchmarkValidationBatch.load_results(run_dir)
  evidence_path = File.join(final_root, "manifest.yaml")
  evidence = LocalEvaluation.load_yaml(evidence_path)
  records_path = File.join(final_root, "corrections.jsonl")
  records = TimingAudit.load_jsonl(records_path)
  all_ids = File.readlines(File.join(final_root, "correction-ids.txt"), chomp: true)
  raise "Incomplete shared corrected validation" unless results.map(&:id_string).sort == all_ids && manifest.runs.keys.sort == all_ids
  raise "Wrong corrected source commit" unless manifest.data.dig("experiment_repository", "commit") == evidence.dig("corrected_source", "commit")
  dispositions_path = File.join(final_root, "validation-failures.json")
  failures = BenchmarkValidationBatch.approved_failures(dispositions_path,
    corrected_manifest: manifest, corrected_results: results,
    original_commit: evidence.dig("original_source", "commit"), corrected_commit: evidence.dig("corrected_source", "commit"))
  selected = records.reject { |record| record.fetch("source_batch") == "20260929-135931" }
  ids = selected.map { |record| record.fetch("program_id") }.sort
  raise "Historical scope is not exactly the 32 affected QT implementations" unless ids.size == 32 && ids.uniq.size == 32 && selected.all? { |record| record.fetch("benchmark") == "qtclustering" }
  raise "Failed revalidation in historical selection" unless (ids & failures.keys).empty?
  by_id = results.to_h { |result| [result.id_string, result] }
  raise "Historical selection is not fully valid" unless ids.all? { |id| BenchmarkValidationBatch.fully_valid?(by_id.fetch(id)) }
  raise "Unexpected existing benchmark records" unless BenchmarkValidationBatch.full_results(run_dir).empty?
  baseline = LocalEvaluation::BenchmarkConfig.new(baseline_path)
  raise "Wrong inherited baseline" unless baseline.frozen? && baseline.digest == "20153151de0d733792317198c0ee7ebd52fbde6f605771029b205ed976be7970"
  baseline.validate_cells!
  source_root = manifest.data.fetch("experiment_repository").fetch("path")
  bound = BenchmarkValidationBatch.rebound_evidence(evidence, root: source_root,
    original_path: evidence_path, original_sha: LocalEvaluation.sha256_file(evidence_path))
  FileUtils.mkdir_p(plan_root)
  derived = File.join(plan_root, "correction-evidence")
  %w[corrections.jsonl correction-ids.txt].each do |name|
    LocalEvaluation.atomic_write(File.join(derived, name), File.binread(File.join(final_root, name)), mode: 0o444)
  end
  LocalEvaluation.atomic_yaml_with_digest(File.join(derived, "manifest.yaml"), bound, immutable: true)
  # Dry-run the full shared commit proof before writing a benchmark configuration.
  LocalEvaluation::SourceCorrectionAmendment.create!(manifest: manifest, correction_dir: derived,
    revision_mode: "already_corrected", reason: "Remeasure only 32 historical QT programs with accepted timing-only corrections; all other historical measurements remain untouched.", dry_run: true)
  seed = LocalEvaluation::CalibrationSeed.materialize!(run_dir: run_dir, source_path: baseline.data.fetch("seed_path"))
  raise "Seed differs from baseline" unless seed.digest == baseline.data.fetch("seed_sha256")
  proposed = BenchmarkValidationBatch.inherited_config(baseline.data,
    manifest_sha: LocalEvaluation.sha256_file(manifest.path),
    validation_sha: LocalEvaluation.sha256_file(File.join(run_dir, "validation/all_validation_results.yaml")),
    count: results.size, seed_path: seed.path, baseline_path: baseline.path, baseline_sha: baseline.digest)
  LocalEvaluation.atomic_yaml(File.join(run_dir, "benchmark_config.proposed.yaml"), proposed)
  LocalEvaluation::BenchmarkPipeline.freeze_config(run_dir: run_dir)
  frozen = LocalEvaluation::BenchmarkConfig.new(File.join(run_dir, "benchmark_config.yaml"))
  raise "Inherited measurement settings changed" unless frozen.data.fetch("cells") == baseline.data.fetch("cells") && frozen.data.fetch("target_seconds") == baseline.data.fetch("target_seconds")
  amendment = LocalEvaluation::SourceCorrectionAmendment.create!(manifest: manifest, correction_dir: derived,
    revision_mode: "already_corrected", reason: "Remeasure only 32 historical QT programs with accepted timing-only corrections; all other historical measurements remain untouched.")
  LocalEvaluation.atomic_write(File.join(plan_root, "ids.txt"), ids.join("\n") + "\n", mode: 0o444)
  LocalEvaluation.atomic_write(File.join(plan_root, "validation-failures.json"), File.binread(dispositions_path), mode: 0o444)
  LocalEvaluation.atomic_write(File.join(plan_root, "prepare-snapshot.rb"), File.binread(__FILE__), mode: 0o444)
  artifacts = %w[ids.txt validation-failures.json prepare-snapshot.rb correction-evidence/manifest.yaml correction-evidence/corrections.jsonl correction-evidence/correction-ids.txt]
  plan = { "schema_version" => 1, "created_at" => Time.now.utc.iso8601, "run_dir" => run_dir,
    "expected" => ids.size, "ids" => ids, "scope" => "Only corrected historical QT implementations; no new-GPT6 or unrelated historical runs",
    "manifest_sha256" => LocalEvaluation.sha256_file(manifest.path),
    "validation_results_sha256" => LocalEvaluation.sha256_file(File.join(run_dir, "validation/all_validation_results.yaml")),
    "configuration_sha256" => frozen.digest, "baseline_configuration_sha256" => baseline.digest,
    "source_correction_amendment_sha256" => amendment.digest,
    "artifacts" => artifacts.to_h { |name| [name, LocalEvaluation.sha256_file(File.join(plan_root, name))] } }
  LocalEvaluation.atomic_yaml_with_digest(File.join(plan_root, "manifest.yaml"), plan, immutable: true)
  manifest.verify_input_revisions!(operation: "benchmark", selected_ids: ids)
  puts JSON.pretty_generate(expected: ids.size, configuration_sha256: frozen.digest, measurement_settings_unchanged: true, benchmarking_started: false)
ensure
  host_lock.close
  run_lock.close
end
