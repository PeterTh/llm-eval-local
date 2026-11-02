# frozen_string_literal: true
$stdout.sync = true
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix"
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix_review"
require_relative "experiment-supplemental/tools/timing_audit/lib/timing_fix_adjudication"
require_relative "correction-request-pacing"
stage = ARGV.fetch(0)
raise "Expected pilot or full" unless ARGV.size == 1 && %w[pilot full].include?(stage)
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
receipt = JSON.parse(File.read(File.join(campaign, "correction-#{stage}-launch.json")))
receipt.fetch("files").each { |path, sha| raise "Frozen correction input changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
receipt.fetch("retained_responses").each { |path, sha| raise "Accepted correction response changed" unless TimingAudit.sha256_file(path) == sha }
ENV["PATH"] = receipt.fetch("path")
BeamReviewPacing.next_request = Time.iso8601(receipt.fetch("not_before"))
BeamReviewPacing.deadline = Time.iso8601(receipt.fetch("deadline"))
BeamReviewPacing.progress_path = File.join(campaign, "correction-#{stage}-paced-progress.json")
BeamReviewPacing.recoveries = []
TimingFix::ProposalRunner.prepend(BeamCorrectionPacing::Proposal)
TimingFixReview::Runner.prepend(BeamCorrectionPacing::Review)
TimingFixAdjudication::Runner.prepend(BeamCorrectionPacing::Adjudication)
begin
  BeamReviewPacing.checkpoint("starting_corrections", "stage" => stage)
  load receipt.fetch("original_driver")
  receipt.fetch("retained_responses").each { |path, sha| raise "Accepted pilot response changed" unless TimingAudit.sha256_file(path) == sha }
  BeamReviewPacing.checkpoint("awaiting_operator_quality_review", "stage" => stage)
rescue BeamReviewPacing::YieldForFable => error
  BeamReviewPacing.checkpoint("yielded_for_fable_reset", "stage" => stage, "reason" => error.message)
rescue Exception => error
  BeamReviewPacing.checkpoint("stopped", "stage" => stage, "error" => "#{error.class}: #{error.message}")
  raise
end
