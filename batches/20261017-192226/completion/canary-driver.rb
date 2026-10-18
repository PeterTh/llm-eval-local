# frozen_string_literal: true

$stdout.sync = true
require "/tmp/sol61-opencode-evaluation-20261018.bNo4yq/benchmark-orchestration"

scratch = "/tmp/sol61-opencode-evaluation-20261018.bNo4yq"
campaign = "/home/petert/llm_para_campaigns/20261017-192226-sol61-opencode-medium/evaluation"
run = "/home/petert/llm_para_local_evaluation/20261018-sol61-opencode-validation"
phase = "verify_revalidation"
checkpoint = lambda do |extra = {}|
  LocalEvaluation.atomic_write(File.join(campaign, "canary-progress.json"), JSON.pretty_generate({
    "updated_at" => Time.now.utc.iso8601, "pid" => Process.pid, "phase" => phase,
    "driver_sha256" => LocalEvaluation.sha256_file(__FILE__)
  }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  review = JSON.parse(File.read(File.join(campaign, "revalidation-completion-review.json")))
  raise "Revalidation gate not passed" unless review.fetch("verification") == "passed" && review.fetch("native_scientific_validation_passed") == YAML.safe_load_file("/home/petert/llm_timing_fixes/20261018-sol61-opencode-final/manifest.yaml").fetch("record_count")
  raise "Resolved timing gate not passed" unless JSON.parse(File.read(File.join(campaign, "audit-completion-review.json"))).fetch("passed")
  phase = "prepare_inherited_configuration"
  checkpoint.call
  BenchmarkValidationBatch.prepare(run_dir: run,
    baseline_config: "/home/petert/llm_para_local_evaluation/20260819-003427/benchmark_config.yaml",
    corrections: "/home/petert/llm_timing_fixes/20261018-sol61-opencode-final",
    corrected_validation: "/home/petert/llm_para_local_evaluation/20261018-sol61-opencode-corrected",
    original_backup: File.join(scratch, "original-backup"), canary_model: "gpt-6.1-sol-oc-medium")
  phase = "preflight"
  checkpoint.call
  native_driver = File.join(scratch, "local-evaluation-driver.rb")
  raise "Preflight failed" unless system(RbConfig.ruby, native_driver, "preflight", "--run-dir=#{run}")
  phase = "reusable_canaries"
  checkpoint.call
  raise "Canary execution failed" unless system(RbConfig.ruby, native_driver, "benchmark", "--run-dir=#{run}",
    "--ids-file=#{run}/benchmark-campaign/canary-ids.txt")
  phase = "verify_canaries"
  checkpoint.call
  raise "Canary verification failed" unless system(RbConfig.ruby, File.join(scratch, "verify-benchmark-records.rb"), "canary")
  phase = "awaiting_canary_inspection"
  checkpoint.call
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
