# frozen_string_literal: true
$stdout.sync = true
require "open3"
require "fiddle/import"
require_relative "experiment/tools/timing_audit/lib/timing_audit"
require_relative "review-request-pacing"
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
prior = primary + "-replicated-work-luna-20261101"
root = primary + "-replicated-broadcast-luna-20261101"
receipt_path = File.join(campaign, "replicated-broadcast-review-launch-20261101.json")
ids = %w[cahn-hilliard_beam-1.0-oc-medium_hybrid_r4]
mode = ARGV.fetch(0)
raise "Use prepare|run" unless ARGV.size == 1 && %w[prepare run].include?(mode)
if mode == "prepare"
  raise "Broadcast replica review already prepared" if File.exist?(root) || File.exist?(receipt_path)
  parent_path = File.join(campaign, "replicated-work-review-launch-20261101.json")
  parent = JSON.parse(File.read(parent_path))
  parent.fetch("files").each { |path, sha| raise "Focused method changed" unless TimingAudit.sha256_file(path) == sha }
  selection = ids.map { |id| { "program_id" => id, "reason" => "The initial consistency sweep covered no-MPI and runtime-only MPI cases. A cross-check of remaining proposals identified this input-broadcast-only case: verify whether the numerical work independently produces a complete result on every rank, with complete local GPU timing, under the identical user-approved contract. An input broadcast alone does not establish distributed numerical ownership. No verdict is prescribed." } }
  TimingAudit.derive_inventory(parent_root: primary, output_dir: root, ids: ids, provenance: {
    "replicated_work_consistency_review" => { "parent_launch_sha256" => TimingAudit.sha256_file(parent_path), "selection" => selection, "model" => "gpt-5.6-luna", "effort" => "high" } })
  manifest_path = File.join(root, "manifest.yaml")
  manifest = YAML.safe_load_file(manifest_path)
  { "prompt_template_sha256" => "prompt-template.txt", "result_schema_sha256" => "result-schema.json", "runner_sha256" => "runner-snapshot.rb" }.each do |key, name|
    TimingAudit.atomic_write(File.join(root, name), File.binread(File.join(prior, name)))
    manifest.fetch("artifacts")[key] = TimingAudit.sha256_file(File.join(root, name))
  end
  %w[platform-context.txt review-guidance.txt replicated-work-timing-contract.txt].each { |name| TimingAudit.atomic_write(File.join(root, name), File.binread(File.join(prior, name))) }
  TimingAudit.atomic_write(File.join(root, "supplemental-selection.jsonl"), TimingAudit.dump_jsonl(selection))
  TimingAudit.atomic_write(manifest_path, YAML.dump(manifest))
  files = [__FILE__, parent_path, File.join(__dir__, "review-request-pacing.rb"), *Dir[File.join(root, "*")].select { |path| File.file?(path) }]
  receipt = { "prepared_at" => TimingAudit.utc_now, "root" => root, "selected_ids" => ids,
    "files" => files.to_h { |path| [path, TimingAudit.sha256_file(path)] },
    "review_cli_path" => parent.fetch("review_cli_path"), "review_cli_sha256" => parent.fetch("review_cli_sha256"),
    "model" => "gpt-5.6-luna", "effort" => "high", "workers" => 1, "minimum_request_spacing_seconds" => 90,
    "new_reviews" => 1, "source_only" => true, "program_execution_allowed" => false,
    "after_unit" => "llm-beam10-oc-correction-resumed-20261101.service", "source_commit_held" => true }
  TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
  FileUtils.cp(__FILE__, campaign)
  puts JSON.pretty_generate(receipt.except("files"))
  exit
end
receipt = JSON.parse(File.read(receipt_path))
receipt.fetch("files").each { |path, sha| raise "Broadcast review input changed" unless TimingAudit.sha256_file(path) == sha }
raise "Pinned CLI changed" unless TimingAudit.sha256_file(receipt.fetch("review_cli_path")) == receipt.fetch("review_cli_sha256")
progress_path = File.join(campaign, "replicated-broadcast-review-progress-20261101.json")
TimingAudit.atomic_write(progress_path, JSON.pretty_generate({ "phase" => "waiting_for_postfix_reviews", "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "after_unit" => receipt.fetch("after_unit") }) + "\n")
pid_text, status = Open3.capture2("systemctl", "--user", "show", receipt.fetch("after_unit"), "-p", "MainPID", "--value")
raise "Cannot inspect prior unit" unless status.success?
pid = Integer(pid_text.strip)
if pid > 1
  module BroadcastReviewWait
    extend Fiddle::Importer
    dlload "libc.so.6"
    extern "int pidfd_open(int, unsigned int)"
  end
  fd = BroadcastReviewWait.pidfd_open(pid, 0)
  if fd >= 0
    process = IO.for_fd(fd)
    ready = IO.select([process], nil, nil, 14400)
    process.close
    raise "Prior review unit did not finish within four hours" unless ready
  end
end
phase = JSON.parse(File.read(File.join(campaign, "correction-resumed-progress-20261101.json")))
raise "Previous correction stage stopped unexpectedly" unless phase.fetch("phase") == "awaiting_correction_commit_review"
previous = JSON.parse(File.read(File.join(campaign, "correction-resumed-paced-progress-20261101.json")))
ENV["PATH"] = "#{File.dirname(receipt.fetch('review_cli_path'))}:/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin"
BeamReviewPacing.next_request = [Time.now, Time.iso8601(previous.fetch("next_request_not_before"))].max
BeamReviewPacing.deadline = Time.iso8601("2026-11-06T17:00:00Z")
BeamReviewPacing.progress_path = progress_path
BeamReviewPacing.recoveries = []
TimingAudit::AuditRunner.prepend(BeamReviewPacing::Dispatch)
begin
  TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 1, model: "gpt-5.6-luna", effort: "high", retries: 1).run
  BeamReviewPacing.checkpoint("awaiting_replicated_work_review")
rescue Exception => error
  BeamReviewPacing.checkpoint("stopped", "error" => "#{error.class}: #{error.message}")
  raise
end
