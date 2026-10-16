# frozen_string_literal: true

$stdout.sync = true
require_relative "experiment/tools/timing_audit/bin/timing_priority_review"
campaign = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/evaluation"
output = "/home/petert/llm_timing_audit/20261015-sonnet55-mpi-split-supplemental"
phase = "static_supplemental_review"
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(File.join(campaign, "audit-supplemental-progress.json"), JSON.pretty_generate({
    "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
    "driver_sha256" => TimingAudit.sha256_file(__FILE__)
  }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  evidence = JSON.parse(File.read(File.join(campaign, "mpi-split-evidence/evidence.json")))
  raise "Pinned MPI library changed" unless TimingAudit.sha256_file(evidence.fetch("library")) == evidence.fetch("library_sha256")
  unless File.exist?(output)
    TimingPriorityReview.prepare_supplemental(
      main_root: "/home/petert/llm_timing_audit/20261015-sonnet55-qtclustering", output_dir: output,
      selection_path: File.join(campaign, "mpi-split-selection.jsonl"),
      context_path: File.join(campaign, "mpi-split-evidence/supplemental-context.txt"), model: "gpt-6.1-sol")
  end
  TimingAudit::AuditRunner.new(output_dir: output, scope: "full", jobs: 1,
    model: "gpt-6.1-sol", effort: "xhigh").run
  phase = "awaiting_supplemental_finalization"
  checkpoint.call
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
