# frozen_string_literal: true
require "time"
require_relative "experiment/tools/timing_audit/lib/timing_audit"
require_relative "review-request-pacing"
$stdout.sync = true
raise "No arguments expected" unless ARGV.empty?
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
receipt = JSON.parse(File.read(File.join(campaign, "audit-full-resume-20261031-launch.json")))
receipt.fetch("files").each { |path, sha| raise "Frozen review source changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
receipt.fetch("retained_results").each { |path, sha| raise "Accepted review changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
BeamReviewPacing.next_request = Time.iso8601(receipt.fetch("not_before"))
BeamReviewPacing.deadline = Time.iso8601(receipt.fetch("deadline"))
BeamReviewPacing.progress_path = File.join(campaign, "audit-full-resume-20261031-progress.json")
BeamReviewPacing.recoveries = []
TimingAudit::AuditRunner.prepend(BeamReviewPacing::Dispatch)
begin
  BeamReviewPacing.checkpoint("resuming")
  load receipt.fetch("original_driver")
  receipt.fetch("retained_results").each { |path, sha| raise "Accepted review changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
  BeamReviewPacing.checkpoint("complete")
rescue BeamReviewPacing::YieldForFable => error
  BeamReviewPacing.checkpoint("yielded_for_fable_reset", "reason" => error.message)
rescue Exception => error
  BeamReviewPacing.checkpoint("stopped", "error" => "#{error.class}: #{error.message}")
  raise
end
