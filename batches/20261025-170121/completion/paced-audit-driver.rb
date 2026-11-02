# frozen_string_literal: true
require "time"
require_relative "experiment/tools/timing_audit/lib/timing_audit"
require_relative "review-request-pacing"
$stdout.sync = true
stage = ARGV.fetch(0)
raise "Expected pilot or full" unless ARGV.size == 1 && %w[pilot full].include?(stage)
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
receipt = JSON.parse(File.read(File.join(campaign, "audit-#{stage}-paced-launch.json")))
receipt.fetch("files").each { |path, sha| raise "Paced review source changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
receipt.fetch("retained_results").each { |path, sha| raise "Accepted review changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
BeamReviewPacing.next_request = Time.iso8601(receipt.fetch("not_before"))
BeamReviewPacing.deadline = Time.iso8601(receipt.fetch("deadline"))
BeamReviewPacing.progress_path = File.join(campaign, "audit-#{stage}-paced-progress.json")
BeamReviewPacing.recoveries = []
TimingAudit::AuditRunner.prepend(BeamReviewPacing::Dispatch)
begin
  BeamReviewPacing.checkpoint("starting")
  load receipt.fetch("original_driver")
  receipt.fetch("retained_results").each { |path, sha| raise "Accepted review changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
  BeamReviewPacing.checkpoint("complete")
rescue BeamReviewPacing::YieldForFable => error
  BeamReviewPacing.checkpoint("yielded_for_fable_reset", "reason" => error.message)
rescue Exception => error
  BeamReviewPacing.checkpoint("stopped", "error" => "#{error.class}: #{error.message}")
  raise
end
