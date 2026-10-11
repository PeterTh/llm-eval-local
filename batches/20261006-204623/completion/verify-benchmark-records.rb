# frozen_string_literal: true

# Recorded-evidence verification only; never executes generated programs.
require "/tmp/sol61-evaluation-20261010.xL0RJx/experiment/tools/timing_audit/bin/benchmark_validation_batch"

mode = ARGV.fetch(0)
raise "Use canary or complete" unless %w[canary complete].include?(mode)
run = "/home/petert/llm_para_local_evaluation/20261010-sol61-validation"
campaign = "/home/petert/llm_para_campaigns/20261006-204623-sol61-medium-xhigh/evaluation"
plan_root = File.join(run, "benchmark-campaign")
plan = BenchmarkValidationBatch.campaign_data(run)
baseline = LocalEvaluation::BenchmarkConfig.new("/home/petert/llm_para_local_evaluation/20260819-003427/benchmark_config.yaml")
raise "Historical configuration changed" unless baseline.digest == "20153151de0d733792317198c0ee7ebd52fbde6f605771029b205ed976be7970"
raise "MPI implementation supporting the scoped makespan proof changed" unless
  LocalEvaluation.sha256_file("/usr/lib/x86_64-linux-gnu/libmpi.so.40.30.6") == "9055018b12757e830591aa0283e485e471f1f2a06d3bc0dd5fb35ab00386c172"
config = LocalEvaluation::BenchmarkConfig.new(File.join(run, "benchmark_config.yaml"))
raise "Measurement settings changed" unless config.data.fetch("cells") == baseline.data.fetch("cells") && config.data.fetch("target_seconds") == baseline.data.fetch("target_seconds")
raise "Unexpected partition" unless plan.values_at("valid_programs", "unchanged_programs", "corrected_programs") == [439, 428, 11] && plan.fetch("excluded_validation_ids").empty?
unchanged = File.readlines(File.join(plan_root, "unchanged-ids.txt"), chomp: true)
corrected = File.readlines(File.join(plan_root, "corrected-ids.txt"), chomp: true)
canaries = File.readlines(File.join(plan_root, "canary-ids.txt"), chomp: true)
expected_canaries = %w[omp_r1 cuda_r1 mpi_r1 hybrid_r1].map { |suffix| "black-scholes_gpt-6.1-sol-medium_#{suffix}" }
raise "Canary selection changed" unless canaries.sort == expected_canaries.sort
ids = mode == "canary" ? canaries.sort : (unchanged + corrected).sort
results = BenchmarkValidationBatch.full_results(run)
raise "Unexpected completed IDs" unless results.keys.sort == ids
manifest = LocalEvaluation::Manifest.new(run)
manifest.verify_input_revisions!(operation: "benchmark", selected_ids: mode == "canary" ? canaries : corrected)
guard = BenchmarkValidationBatch.verify_partition!(run, ids)
invocations = LocalEvaluation.load_yaml(File.join(run, "benchmark/benchmark_run_metadata.yaml")).fetch("invocations")
expected_invocations = mode == "canary" ? [[4, 4]] : [[4, 4], [428, 424], [11, 11]]
raise "Unexpected invocation or retry" unless invocations.map { |entry| entry.values_at("selected", "pending") } == expected_invocations && invocations.all? { |entry| entry.fetch("retry_failed") == false }
raise "Unexpected archived attempt" unless Dir[File.join(run, "benchmark/attempts/*/*")].empty?
original_sha = LocalEvaluation.sha256_file(File.join(run, "validation/all_validation_results.yaml"))
raise "Original validation changed" unless original_sha == "d8647fec22006f9c9ef0f8db6532ffb989a3200839eca6390e51d295cea736ad"
corrected_root = plan.fetch("corrected_validation").fetch("run_dir")
raise "Corrected validation changed" unless LocalEvaluation.sha256_file(File.join(corrected_root, "validation/all_validation_results.yaml")) == plan.dig("corrected_validation", "results_sha256")
failures = results.filter_map do |id, record|
  next if record.first == true
  metadata = LocalEvaluation.load_yaml(File.join(run, "benchmark", id, "benchmark_metadata.yaml"))
  execution = metadata.fetch("executions").find { |entry| !entry.fetch("success") }
  parse_errors = Dir[File.join(run, "benchmark", id, "*parse_error.log")]
  classification = if metadata["build_success"] == false
                     "build_failure"
                   elsif execution&.fetch("timed_out")
                     "#{execution.fetch('repetition') == 'warmup' ? 'warmup' : 'measurement'}_timeout"
                   elsif execution
                     "program_exit_failure"
                   elsif !parse_errors.empty?
                     "metric_parse_failure"
                   else
                     raise "Unclassified benchmark failure: #{id}"
                   end
  { "id" => id, "classification" => classification, "execution" => execution,
    "build_error" => metadata["build_error"], "parse_error_paths" => parse_errors }
end
report = {
  "schema_version" => 1, "checked_at" => Time.now.utc.iso8601,
  "checker_sha256" => LocalEvaluation.sha256_file(__FILE__), "verification" => "passed",
  "completed" => results.size, "successful" => results.size - failures.size, "failures" => failures,
  "warmups_per_program" => 1, "measurements_per_successful_program" => BENCHMARK_COUNT,
  "all_44_cells_unchanged" => true, "configuration_sha256" => config.digest,
  "baseline_configuration_sha256" => baseline.digest,
  "campaign_manifest_sha256" => LocalEvaluation.sha256_file(File.join(plan_root, "manifest.yaml")),
  "pipeline_source_sha256" => manifest.data.fetch("pipeline_source").fetch("sha256"),
  "original_validation_sha256" => original_sha,
  "corrected_validation_sha256" => plan.dig("corrected_validation", "results_sha256"),
  "invocations" => invocations, "no_retries_or_repeated_completed_measurements" => true,
  "scope" => "Only the new Sol 6.1 batch; no historical re-execution"
}
if mode == "canary"
  raise "Canary failure requires inspection" unless failures.empty?
  report.merge!("quality_gate" => "passed", "canary_ids" => canaries, "guard" => guard,
    "results" => results, "policy" => "Unchanged inherited settings and native consistency checks; retain all canaries without re-execution")
  output = File.join(campaign, "benchmark-canary-gate.json")
else
  progress = JSON.parse(File.read(File.join(campaign, "benchmark-progress.json")))
  raise "Campaign not complete" unless progress.fetch("phase") == "complete"
  unchanged_guard = LocalEvaluation.load_yaml(File.join(plan_root, "unchanged-benchmarks-guard.yaml"))
  raise "Unchanged records changed" unless BenchmarkValidationBatch.verify_partition!(run, unchanged) == unchanged_guard
  canary_gate = JSON.parse(File.read(File.join(campaign, "benchmark-canary-gate.json")))
  raise "Canaries changed" unless BenchmarkValidationBatch.verify_partition!(run, canaries) == canary_gate.fetch("guard")
  TimingAudit::SourceRepository.new(root: plan.fetch("original_source_backup"), commit: plan.dig("original_source", "commit"))
  report.merge!("completed_at" => progress.fetch("updated_at"),
    "records_sha256" => guard.fetch("records_sha256"),
    "metadata_digests_sha256" => Digest::SHA256.hexdigest(JSON.generate(guard.fetch("metadata_sha256"))),
    "all_records_reconciled" => true, "unchanged_partition_preserved" => true, "canaries_preserved" => true,
    "timing_fixed_records" => corrected.size, "validation_passed" => 439, "validation_failed" => 1,
    "validation_failure_ids" => ["matmul_gpt-6.1-sol-medium_mpi_r1"],
    "by_backend" => ids.group_by { |id| manifest.runs.fetch(id).fetch("par_type") }.transform_values { |group|
      { "completed" => group.size, "successful" => group.count { |id| results.fetch(id).first == true } }
    },
    "integration_status" => "Pending curated package/release integration; no push or deployment performed")
  output = File.join(campaign, "benchmark-completion-review.json")
end
raise "Report already exists" if File.exist?(output)
LocalEvaluation.atomic_write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
