# frozen_string_literal: true
$stdout.sync = true
require "open3"
require_relative "experiment/tools/timing_audit/lib/timing_audit"
require_relative "review-request-pacing"
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
prior = primary + "-replicated-work-luna-20261101"
root = primary + "-replicated-work-extra-luna-20261101"
receipt_path = File.join(campaign, "replicated-work-extra-review-launch-20261101.json")
ids = %w[cahn-hilliard_beam-1.0-oc-medium_hybrid_r1 qtclustering_beam-1.0-oc-medium_hybrid_r3 roomsim_beam-1.0-oc-medium_hybrid_r3 unstructured_beam-1.0-oc-medium_hybrid_r2]
mode = ARGV.fetch(0)
raise "Use prepare|run" unless ARGV.size == 1 && %w[prepare run].include?(mode)
if mode == "prepare"
  raise "Additional review already prepared" if File.exist?(root) || File.exist?(receipt_path)
  parent_receipt_path = File.join(campaign, "replicated-work-review-launch-20261101.json")
  parent = JSON.parse(File.read(parent_receipt_path))
  parent.fetch("files").each { |path, sha| raise "Focused method changed" unless TimingAudit.sha256_file(path) == sha }
  authorization_path = File.join(campaign, "replicated-work-user-decision-20261101.json")
  TimingAudit.derive_inventory(parent_root: primary, output_dir: root, ids: ids, provenance: {
    "replicated_work_consistency_review" => { "authorization_sha256" => TimingAudit.sha256_file(authorization_path),
      "prior_focused_manifest_sha256" => TimingAudit.sha256_file(File.join(prior, "manifest.yaml")),
      "reason" => "A static MPI-call inventory found four additional hybrid cases with only runtime/communicator/barrier calls and no numerical communication. Verify complete-result ownership and local timing under the identical clarified contract; no verdict is prescribed." } })
  manifest_path = File.join(root, "manifest.yaml")
  manifest = YAML.safe_load_file(manifest_path)
  { "prompt_template_sha256" => "prompt-template.txt", "result_schema_sha256" => "result-schema.json", "runner_sha256" => "runner-snapshot.rb" }.each do |key, name|
    TimingAudit.atomic_write(File.join(root, name), File.binread(File.join(prior, name)))
    manifest.fetch("artifacts")[key] = TimingAudit.sha256_file(File.join(root, name))
  end
  %w[platform-context.txt review-guidance.txt replicated-work-timing-contract.txt].each { |name| TimingAudit.atomic_write(File.join(root, name), File.binread(File.join(prior, name))) }
  TimingAudit.atomic_write(manifest_path, YAML.dump(manifest))
  files = [__FILE__, parent_receipt_path, authorization_path, File.join(__dir__, "review-request-pacing.rb"), *Dir[File.join(root, "*")].select { |path| File.file?(path) }]
  receipt = { "prepared_at" => TimingAudit.utc_now, "root" => root, "selected_ids" => ids,
    "files" => files.to_h { |path| [path, TimingAudit.sha256_file(path)] },
    "review_cli_path" => parent.fetch("review_cli_path"), "review_cli_sha256" => parent.fetch("review_cli_sha256"),
    "model" => "gpt-5.6-luna", "effort" => "high", "workers" => 1, "minimum_request_spacing_seconds" => 90,
    "new_reviews" => 4, "prior_five_not_repeated" => true, "source_only" => true }
  TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
  FileUtils.cp(__FILE__, campaign)
  puts JSON.pretty_generate(receipt.except("files"))
  exit
end
receipt = JSON.parse(File.read(receipt_path))
receipt.fetch("files").each { |path, sha| raise "Additional review input changed" unless TimingAudit.sha256_file(path) == sha }
raise "Pinned CLI changed" unless TimingAudit.sha256_file(receipt.fetch("review_cli_path")) == receipt.fetch("review_cli_sha256")
state, status = Open3.capture2("systemctl", "--user", "show", "llm-beam10-oc-replicated-work-20261101.service", "-p", "ActiveState", "--value")
raise "First focused review still active" unless status.success? && state.strip == "inactive"
prior_progress = JSON.parse(File.read(File.join(campaign, "replicated-work-review-progress-20261101.json")))
raise "First focused review did not finish" unless prior_progress.fetch("phase") == "awaiting_replicated_work_review"
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
ENV["PATH"] = "#{File.dirname(receipt.fetch('review_cli_path'))}:/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin"
BeamReviewPacing.next_request = [Time.now, Time.iso8601(prior_progress.fetch("next_request_not_before"))].max
BeamReviewPacing.deadline = Time.iso8601("2026-11-06T17:00:00Z")
BeamReviewPacing.progress_path = File.join(campaign, "replicated-work-extra-review-progress-20261101.json")
BeamReviewPacing.recoveries = []
TimingAudit::AuditRunner.prepend(BeamReviewPacing::Dispatch)
begin
  TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 1, model: "gpt-5.6-luna", effort: "high", retries: 1).run
  BeamReviewPacing.checkpoint("awaiting_replicated_work_review")
rescue Exception => error
  BeamReviewPacing.checkpoint("stopped", "error" => "#{error.class}: #{error.message}")
  raise
end
