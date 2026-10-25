# frozen_string_literal: true

$stdout.sync = true
require "/tmp/sonnet5-isolated-evaluation-20261025-20261025-747035-lhzhiq/benchmark-orchestration"

run = "/home/petert/llm_para_local_evaluation/20261025-sonnet5-isolated-validation"
campaign = "/home/petert/llm_para_campaigns/20261025-143725-sonnet5-isolated-replacements/evaluation"
expected_corrections = YAML.safe_load_file("/home/petert/llm_timing_fixes/20261025-sonnet5-isolated-final/manifest.yaml").fetch("record_count")
phase = "verify_inputs"
checkpoint = lambda do |extra = {}|
  LocalEvaluation.atomic_write(File.join(campaign, "benchmark-progress.json"), JSON.pretty_generate({
    "updated_at" => Time.now.utc.iso8601, "pid" => Process.pid, "phase" => phase,
    "expected" => 6, "driver_sha256" => LocalEvaluation.sha256_file(__FILE__)
  }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  plan = BenchmarkValidationBatch.campaign_data(run)
  raise "Benchmark selection changed" unless plan.values_at("valid_programs", "unchanged_programs", "corrected_programs") == [6, 6 - expected_corrections, expected_corrections] && plan.fetch("excluded_validation_ids").empty?
  gate = JSON.parse(File.read(File.join(campaign, "benchmark-canary-gate.json")))
  raise "Canary gate not passed" unless gate.fetch("quality_gate") == "passed"
  raise "Canary evidence changed" unless BenchmarkValidationBatch.verify_partition!(run, gate.fetch("canary_ids")) == gate.fetch("guard")
  raise "Configuration differs from canary gate" unless plan.fetch("configuration_sha256") == gate.fetch("configuration_sha256")
  phase = "benchmarking"
  checkpoint.call
  BenchmarkValidationBatch.run(run_dir: run)
  raise "Canaries were changed or repeated" unless BenchmarkValidationBatch.verify_partition!(run, gate.fetch("canary_ids")) == gate.fetch("guard")
  results = BenchmarkValidationBatch.full_results(run)
  phase = "complete"
  checkpoint.call("completed" => results.size,
    "successful" => results.count { |_id, record| record.first == true },
    "failed_ids" => results.filter_map { |id, record| id unless record.first == true })
  verifier = "/tmp/sonnet5-isolated-evaluation-20261025-20261025-747035-lhzhiq/verify-benchmark-records.rb"
  raise "Completed benchmark evidence verification failed" unless system(RbConfig.ruby, verifier, "complete")
  puts "Completed #{results.size} new Sonnet 5 isolated replacement benchmarks; no historical re-execution"
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
