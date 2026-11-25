# frozen_string_literal: true
require_relative "observer-pipeline-v3/tools/validation_audit/spmv_native_review"

evaluation = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation"
validation = "/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v3"
evidence = File.join(evaluation, "spmv-review")
raise "SpMV preparation already exists" if File.exist?(evidence)
completion = JSON.parse(File.read(File.join(validation, "validation-completion-review.json")))
raise "Validation is incomplete" unless completion.fetch("completed") == 440 && completion.fetch("infrastructure_errors").empty?
state, = Open3.capture2("systemctl", "--user", "show", "llm-gpt62-medium-validation-20261125.service", "--property=ActiveState", "--value")
raise "Validation is active" if %w[active activating reloading].include?(state.strip)
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is active" unless status.exitstatus == 1 && pids.empty?
lock = LocalEvaluation::HostPerformanceLock.new
begin
  workspace = Dir.mktmpdir("gpt62-medium-spmv-review-", "/tmp")
  FileUtils.mkdir_p(evidence)
  FileUtils.cp(__FILE__, evidence)
  tool = ValidationAudit::SpmvNativeReview.new(workspace: workspace, evidence: evidence)
  inventory = tool.prepare_inventory(validation: validation)
  raise "Unexpected SpMV selection" unless inventory.fetch("rows").size.between?(0, 40)
  tool.prepare
  pilot_ids = %w[cuda hybrid mpi omp].filter_map do |backend|
    inventory.fetch("rows").find { |row| row.fetch("backend") == backend }&.fetch("id")
  end
  receipt = { "prepared_at" => Time.now.utc.iso8601, "workspace" => workspace, "evidence" => evidence,
    "method_revision" => "3d2298fdbf94863d2de1acd9493a8f479a38ed03",
    "method_script" => File.join(__dir__, "observer-pipeline-v3/tools/validation_audit/spmv_native_review.rb"),
    "validation_run" => validation, "inventory_sha256" => ValidationAudit.sha(File.join(evidence, "native-spmv-inventory.json")),
    "pilot_ids" => pilot_ids, "pilot_review_required_before_full_delegation" => true,
    "reviewer_model" => "gpt-6-luna", "maximum_parallel_luna_reviewers" => 3,
    "program_executions" => 0, "compilation" => 0, "benchmark_runs" => 0, "program_changes" => 0,
    "template" => "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation/spmv-review/prepare-spmv-review.rb",
    "changes" => "Campaign/path identities; derive pilots from eligible backends instead of assuming all 40 programs pass; explicitly refuse preparation while native validation is active." }
  ValidationAudit.save(File.join(evidence, "preparation.json"), receipt)
  puts JSON.pretty_generate(receipt)
ensure
  lock.close
end
