# frozen_string_literal: true

$stdout.sync = true
require "/tmp/gpt6-evaluation-20261001.rhp9wY/experiment/tools/timing_audit/bin/benchmark_validation_batch"

gpt6_run = "/home/petert/llm_para_local_evaluation/20261001-gpt6-validation"
historical_run = "/home/petert/llm_para_local_evaluation/20261001-gpt6-qt-corrected"
historical_plan_root = File.join(historical_run, "historical-benchmark-campaign")
campaign_root = "/home/petert/llm_para_campaigns/20260929-135931-gpt6-medium"
progress_path = File.join(campaign_root, "benchmark-progress.yaml")
phase = "verify_inputs"
checkpoint = lambda do |extra = {}|
  LocalEvaluation.atomic_yaml(progress_path, { "updated_at" => Time.now.utc.iso8601,
    "pid" => Process.pid, "phase" => phase, "new_gpt6_expected" => 609,
    "historical_qt_expected" => 32, "excluded_validation_ids" => ["nbody_gpt-6-luna-medium_hybrid_r5", "roomsim_gpt-6-luna-medium_hybrid_r3"] }.merge(extra))
end
begin
  plan_path = File.join(historical_plan_root, "manifest.yaml")
  raise "Historical benchmark plan digest mismatch" unless File.read("#{plan_path}.sha256").strip == LocalEvaluation.sha256_file(plan_path)
  plan = LocalEvaluation.load_yaml(plan_path)
  plan.fetch("artifacts").each do |name, digest|
    raise "Historical benchmark artifact changed: #{name}" unless LocalEvaluation.sha256_file(File.join(historical_plan_root, name)) == digest
  end
  historical_ids = File.readlines(File.join(historical_plan_root, "ids.txt"), chomp: true)
  raise "Historical benchmark scope changed" unless historical_ids == plan.fetch("ids") && historical_ids.size == 32
  { "manifest_sha256" => "evaluation_manifest.yaml",
    "validation_results_sha256" => "validation/all_validation_results.yaml",
    "configuration_sha256" => "benchmark_config.yaml",
    "source_correction_amendment_sha256" => "source_correction_amendment.yaml" }.each do |key, relative|
    raise "Historical benchmark provenance changed: #{key}" unless plan.fetch(key) == LocalEvaluation.sha256_file(File.join(historical_run, relative))
  end
  gpt6 = BenchmarkValidationBatch.campaign_data(gpt6_run)
  raise "GPT-6 benchmark scope changed" unless gpt6.fetch("valid_programs") == 609 && gpt6.fetch("excluded_validation_ids") == ["nbody_gpt-6-luna-medium_hybrid_r5", "roomsim_gpt-6-luna-medium_hybrid_r3"]
  phase = "new_gpt6"
  checkpoint.call
  BenchmarkValidationBatch.run(run_dir: gpt6_run)
  phase = "historical_qt"
  checkpoint.call
  command = [RbConfig.ruby, "/tmp/local-evaluation-driver-20261001.rb",
    "benchmark", "--run-dir=#{historical_run}", "--ids-file=#{File.join(historical_plan_root, 'ids.txt')}"]
  raise "Historical benchmark pipeline failed" unless system(*command)
  raise "Unexpected historical benchmark IDs" unless BenchmarkValidationBatch.full_results(historical_run).keys.sort == historical_ids
  BenchmarkValidationBatch.verify_partition!(historical_run, historical_ids)
  gpt6_results = BenchmarkValidationBatch.full_results(gpt6_run)
  historical_results = BenchmarkValidationBatch.full_results(historical_run)
  phase = "complete"
  checkpoint.call("new_gpt6_completed" => gpt6_results.size,
    "new_gpt6_successful" => gpt6_results.count { |_id, record| record.first == true },
    "historical_qt_completed" => historical_results.size,
    "historical_qt_successful" => historical_results.count { |_id, record| record.first == true },
    "new_gpt6_failed_ids" => gpt6_results.filter_map { |id, record| id unless record.first == true },
    "historical_qt_failed_ids" => historical_results.filter_map { |id, record| id unless record.first == true })
  puts "Completed scoped campaign: #{gpt6_results.size} new GPT-6 and #{historical_results.size} historical QT benchmarks"
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
