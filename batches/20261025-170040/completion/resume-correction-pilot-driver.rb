# frozen_string_literal: true

# Operational recovery only: retain all accepted proposals and failed attempts.
$stdout.sync = true
require_relative "experiment/tools/timing_audit/lib/timing_fix"

campaign = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation"
proposals = "/home/petert/llm_timing_fixes/20261028-haiku55-opencode-proposals"
original_driver = File.join(__dir__, "correction-pilot-driver.rb")
launch = JSON.parse(File.read(File.join(campaign, "correction-pilot-launch.json")))
raise "Original driver changed" unless TimingAudit.sha256_file(original_driver) == launch.fetch("driver_sha256")
progress = JSON.parse(File.read(File.join(campaign, "correction-pilot-progress.json")))
raise "Unexpected recovery boundary" unless progress.fetch("phase") == "stopped" && progress.fetch("stopped_phase") == "proposal_pilot"
ids = File.readlines(File.join(proposals, "trial-ids.txt"), chomp: true).reject(&:empty?)
raise "Pilot selection changed" unless ids.size == 16 && ids.uniq == ids
retained = Dir[File.join(proposals, "proposals/*.json")].sort.to_h { |path| [path, TimingAudit.sha256_file(path)] }
raise "Unexpected accepted proposal count" unless retained.size == 6
phase = "serial_pending_proposals"
active_id = nil
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(File.join(campaign, "correction-pilot-recovery-progress.json"), JSON.pretty_generate({
    "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
    "active_id" => active_id, "driver_sha256" => TimingAudit.sha256_file(__FILE__),
    "original_driver_sha256" => launch.fetch("driver_sha256"),
    "retained_proposals" => retained,
    "policy" => "One source-only Sol6.1/high proposal at a time, one attempt per invocation, fail-fast. No model, prompt, code-under-review or scientific execution changes. Resume the immutable original pilot driver after proposal completion."
  }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  ids.each do |id|
    active_id = id
    checkpoint.call
    TimingFix::ProposalRunner.new(output_dir: proposals, scope: "trial", jobs: 1,
      model: "gpt-6.1-sol", effort: "high", retries: 1, only_ids: [id]).run
  end
  retained.each { |path, digest| raise "Accepted proposal changed" unless TimingAudit.sha256_file(path) == digest }
  TimingFix::ProposalVerifier.new(proposals, "trial").run
  phase = "resume_original_pilot_driver"
  active_id = nil
  checkpoint.call
  load original_driver
  phase = "complete"
  checkpoint.call
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
