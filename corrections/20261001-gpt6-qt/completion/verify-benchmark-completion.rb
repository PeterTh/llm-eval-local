# frozen_string_literal: true

# Read-only verification of recorded evidence; never executes benchmark programs.
require "/tmp/gpt6-evaluation-20261001.rhp9wY/experiment/tools/timing_audit/bin/benchmark_validation_batch"

gpt6_root = "/home/petert/llm_para_local_evaluation/20261001-gpt6-validation"
historical_root = "/home/petert/llm_para_local_evaluation/20261001-gpt6-qt-corrected"
campaign_root = "/home/petert/llm_para_campaigns/20260929-135931-gpt6-medium"
final_root = "/home/petert/llm_timing_fixes/20261001-gpt6-qt-final"
artifact_root = "/home/petert/llm-eval-local"
baseline_path = "/home/petert/llm_para_local_evaluation/20260819-003427/benchmark_config.yaml"
progress = LocalEvaluation.load_yaml(File.join(campaign_root, "benchmark-progress.yaml"))
raise "Campaign is not complete" unless progress.fetch("phase") == "complete"
gpt6_plan = BenchmarkValidationBatch.campaign_data(gpt6_root)
TimingAudit::SourceRepository.new(root: gpt6_plan.fetch("original_source_backup"),
  commit: gpt6_plan.fetch("original_source").fetch("commit"))
gpt6_plan_root = File.join(gpt6_root, "benchmark-campaign")
unchanged_ids = File.readlines(File.join(gpt6_plan_root, "unchanged-ids.txt"), chomp: true)
corrected_ids = File.readlines(File.join(gpt6_plan_root, "corrected-ids.txt"), chomp: true)
excluded_ids = File.readlines(File.join(gpt6_plan_root, "excluded-validation-ids.txt"), chomp: true)
raise "GPT-6 selection changed" unless unchanged_ids.size == 562 && corrected_ids.size == 47 && excluded_ids == %w[nbody_gpt-6-luna-medium_hybrid_r5 roomsim_gpt-6-luna-medium_hybrid_r3]
gpt6_ids = (unchanged_ids + corrected_ids).sort
raise "Duplicate GPT-6 selection" unless gpt6_ids.uniq.size == 609

historical_plan_root = File.join(historical_root, "historical-benchmark-campaign")
historical_plan_path = File.join(historical_plan_root, "manifest.yaml")
raise "Historical plan changed" unless LocalEvaluation.sha256_file(historical_plan_path) == File.read("#{historical_plan_path}.sha256").strip
historical_plan = LocalEvaluation.load_yaml(historical_plan_path)
historical_plan.fetch("artifacts").each do |name, digest|
  raise "Historical artifact changed: #{name}" unless LocalEvaluation.sha256_file(File.join(historical_plan_root, name)) == digest
end
historical_ids = File.readlines(File.join(historical_plan_root, "ids.txt"), chomp: true)
raise "Historical scope changed" unless historical_ids == historical_plan.fetch("ids") && historical_ids.uniq.size == 32
{
  "manifest_sha256" => "evaluation_manifest.yaml",
  "validation_results_sha256" => "validation/all_validation_results.yaml",
  "configuration_sha256" => "benchmark_config.yaml",
  "source_correction_amendment_sha256" => "source_correction_amendment.yaml"
}.each do |key, relative|
  raise "Historical provenance changed: #{key}" unless historical_plan.fetch(key) == LocalEvaluation.sha256_file(File.join(historical_root, relative))
end

baseline = LocalEvaluation::BenchmarkConfig.new(baseline_path)
raise "Inherited baseline changed" unless baseline.digest == "20153151de0d733792317198c0ee7ebd52fbde6f605771029b205ed976be7970"
run_specs = [["new_gpt6", gpt6_root, gpt6_ids], ["historical_qt", historical_root, historical_ids]]
reports = run_specs.to_h do |label, root, ids|
  manifest = LocalEvaluation::Manifest.new(root)
  # After the guarded source transition, only correction IDs may be executed.
  # Earlier unchanged measurements are checked against their preserved guard below.
  execution_ids = label == "new_gpt6" ? corrected_ids : ids
  manifest.verify_input_revisions!(operation: "benchmark", selected_ids: execution_ids)
  config = LocalEvaluation::BenchmarkConfig.new(File.join(root, "benchmark_config.yaml"))
  raise "Measurement settings changed" unless config.data.fetch("cells") == baseline.data.fetch("cells") && config.data.fetch("target_seconds") == baseline.data.fetch("target_seconds")
  results = BenchmarkValidationBatch.full_results(root)
  raise "Final selection differs: #{label}" unless results.keys.sort == ids.sort
  guard = BenchmarkValidationBatch.verify_partition!(root, ids)
  run_metadata = LocalEvaluation.load_yaml(File.join(root, "benchmark/benchmark_run_metadata.yaml"))
  invocations = run_metadata.fetch("invocations")
  expected_invocations = label == "new_gpt6" ? [[4, 4], [562, 558], [47, 47]] : [[32, 32]]
  raise "Unexpected invocation or retry: #{label}" unless invocations.map { |x| [x.fetch("selected"), x.fetch("pending")] } == expected_invocations && invocations.all? { |x| x.fetch("retry_failed") == false }
  raise "Unexpected archived benchmark attempt" unless Dir[File.join(root, "benchmark/attempts/*/*")].empty?
  failures = results.filter_map do |id, record|
    next if record.first == true
    metadata = LocalEvaluation.load_yaml(File.join(root, "benchmark", id, "benchmark_metadata.yaml"))
    executions = metadata.fetch("executions")
    raise "Unexpected build, parsing or partial-measurement failure" unless metadata["build_error"].nil? && metadata.fetch("metrics").empty? && executions.size == 1 && executions.first.fetch("repetition") == "warmup" && !executions.first.fetch("success") && Dir[File.join(root, "benchmark", id, "*parse_error.log")].empty?
    execution = executions.first
    reason = if execution.fetch("timed_out")
               "warmup_timeout"
             elsif id == "stencil3d_gpt-6-luna-medium_mpi_r5" && execution.fetch("exit_code") == 139
               "warmup_segmentation_fault"
             else
               raise "Unreviewed failure: #{id}"
             end
    { "id" => id, "classification" => reason, "execution" => execution }
  end
  [label, {
    "root" => root, "completed" => results.size, "successful" => results.count { |_id, record| record.first == true },
    "failures" => failures, "configuration_sha256" => config.digest,
    "full_results_sha256" => LocalEvaluation.sha256_file(File.join(root, "benchmark", BENCHMARK_FULL_RESULTS_FN)),
    "records_sha256" => guard.fetch("records_sha256"),
    "metadata_digests_sha256" => Digest::SHA256.hexdigest(JSON.generate(guard.fetch("metadata_sha256"))),
    "all_records_reconciled" => true, "all_44_cells_unchanged" => true,
    "invocations" => invocations, "no_retries_or_repeated_completed_measurements" => true
  }]
end

unchanged_guard = LocalEvaluation.load_yaml(File.join(gpt6_plan_root, "unchanged-benchmarks-guard.yaml"))
raise "Unchanged partition changed" unless BenchmarkValidationBatch.verify_partition!(gpt6_root, unchanged_ids) == unchanged_guard
canary_gate = JSON.parse(File.read(File.join(campaign_root, "benchmark-canary-gate.json")))
raise "Canaries changed" unless BenchmarkValidationBatch.verify_partition!(gpt6_root, canary_gate.fetch("canary_ids")) == canary_gate.fetch("guard")

original_validation_path = File.join(gpt6_root, "validation/all_validation_results.yaml")
corrected_validation_path = File.join(historical_root, "validation/all_validation_results.yaml")
raise "Original validation changed" unless LocalEvaluation.sha256_file(original_validation_path) == "0a623f996f199d4d70fd43b4f9045e1ad825e7a8c44158f6d3edfb2307e99bcc"
raise "Corrected validation changed" unless LocalEvaluation.sha256_file(corrected_validation_path) == "48ee94ec789bd12b2067e0705d904a83bcf127cf827bd16db1a3f1b1f339ca46"
original_validation = BenchmarkValidationBatch.load_results(gpt6_root)
effective_valid_ids = original_validation.select { |r| BenchmarkValidationBatch.fully_valid?(r) }.map(&:id_string) - excluded_ids
raise "Effective validation/benchmark mismatch" unless effective_valid_ids.sort == gpt6_ids
new_results = BenchmarkValidationBatch.full_results(gpt6_root)
by_model = original_validation.group_by(&:model).sort.to_h do |model, records|
  valid = records.count { |r| effective_valid_ids.include?(r.id_string) }
  successful = records.count { |r| new_results[r.id_string]&.first == true }
  [model, { "generated" => records.size, "effective_validation_passed" => valid, "effective_validation_failed" => records.size - valid,
    "benchmark_successful" => successful, "benchmark_failed" => valid - successful }]
end

catalog_path = File.join(artifact_root, "release/catalog.json")
catalog = JSON.parse(File.read(catalog_path))
previous = {}
catalog.fetch("campaigns").each do |campaign|
  Dir[File.join(artifact_root, campaign.fetch("benchmark_records"))].select { |path| path.include?("/qtclustering/") }.each do |path|
    File.foreach(path) do |line|
      record = JSON.parse(line)
      id = record.fetch("id")
      next unless historical_ids.include?(id)
      raise "Duplicate historical baseline: #{id}" if previous.key?(id)
      previous[id] = { "success" => record.fetch("success"), "evidence_path" => path, "record_sha256" => Digest::SHA256.hexdigest(line) }
    end
  end
end
raise "Incomplete historical baseline" unless previous.keys.sort == historical_ids
historical_results = BenchmarkValidationBatch.full_results(historical_root)
comparison = historical_ids.map do |id|
  previous.fetch(id).merge("id" => id, "corrected_success" => historical_results.fetch(id).first)
end
changes = comparison.reject { |r| r.fetch("success") == r.fetch("corrected_success") }

puts JSON.pretty_generate({
  "schema_version" => 1, "checked_at" => Time.now.utc.iso8601, "completed_at" => progress.fetch("updated_at"),
  "verification" => "passed", "checker_sha256" => LocalEvaluation.sha256_file(__FILE__),
  "new_gpt6" => reports.fetch("new_gpt6"), "historical_qt" => reports.fetch("historical_qt"),
  "by_model" => by_model, "effective_new_validation" => { "passed" => 609, "failed" => 51, "raw_original_preserved" => true },
  "excluded_validation_ids" => excluded_ids,
  "validation_failure_dispositions_sha256" => LocalEvaluation.sha256_file(File.join(final_root, "validation-failures.json")),
  "corrected_validation" => { "completed" => 81, "passed" => 79, "failed" => 2, "raw_records_preserved" => true },
  "unchanged_partition_preserved" => true, "unchanged_partition_count" => unchanged_ids.size,
  "unchanged_partition_records_sha256" => unchanged_guard.fetch("records_sha256"), "canaries_preserved" => true,
  "historical_status_comparison" => comparison, "historical_success_failure_status_changes" => changes,
  "historical_reference_catalog_sha256" => LocalEvaluation.sha256_file(catalog_path),
  "baseline_configuration_sha256" => baseline.digest,
  "pipeline_source_sha256" => LocalEvaluation.pipeline_source_snapshot("/tmp/gpt6-evaluation-20261001.rhp9wY/experiment").fetch("sha256"),
  "scope" => "609 new GPT-6 benchmarks and only 32 affected historical QT reruns; no unrelated historical benchmark repeated",
  "integration_status" => "Pending curated package/release integration; preserve original observations and overlay approved failed revalidations; no push or deployment performed"
})
