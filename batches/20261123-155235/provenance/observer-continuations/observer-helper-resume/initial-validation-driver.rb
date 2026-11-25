# frozen_string_literal: true

$stdout.sync = true
require "/tmp/gpt62-medium-evaluation-20261125-ozfKL7/observer-pipeline-v3/lib/local_evaluation"
campaign = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation"
root = "/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3"
checkpoint = lambda do |status, extra = {}|
  LocalEvaluation.atomic_write(File.join(campaign, "validation-progress.json"), JSON.pretty_generate({
    "updated_at" => Time.now.utc.iso8601, "pid" => Process.pid, "phase" => status,
    "driver_sha256" => LocalEvaluation.sha256_file(__FILE__), "run_dir" => root
  }.merge(extra)) + "\n")
end
begin
  checkpoint.call("validating")
  command = ["/usr/bin/ruby", "/tmp/gpt62-medium-evaluation-20261125-ozfKL7/local-evaluation-driver.rb", "validate", "--run-dir=#{root}"]
  raise "Native validation stopped with #{$?.exitstatus}" unless system(*command)
  checkpoint.call("verifying_completion")
  load "/tmp/gpt62-medium-evaluation-20261125-ozfKL7/verify-validation-completion.rb"
  FileUtils.cp(File.join(root, "validation-completion-review.json"), campaign)
  checkpoint.call("awaiting_validation_review")
rescue Exception => error
  checkpoint.call("stopped", "error" => "#{error.class}: #{error.message}")
  raise
end
