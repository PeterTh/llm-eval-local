# frozen_string_literal: true
$stdout.sync = true
require "open3"
require_relative "experiment/tools/timing_audit/bin/timing_priority_review"
require_relative "review-request-pacing"
mode = ARGV.fetch(0)
raise "Expected prepare or run" unless ARGV.size == 1 && %w[prepare run].include?(mode)
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
old_root = primary + "-supplemental-20261031"
root = primary + "-supplemental-communication-20261031"
receipt_path = File.join(campaign, "audit-supplemental-communication-20261031-launch.json")

if mode == "prepare"
  raise "Extension already prepared" if File.exist?(root) || File.exist?(receipt_path)
  old_receipt_path = File.join(campaign, "audit-supplemental-20261031-launch.json")
  old_receipt = JSON.parse(File.read(old_receipt_path))
  %w[files retained_results prior_final].each do |key|
    old_receipt.fetch(key).each { |path, sha| raise "Prior evidence changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
  end
  state, status = Open3.capture2("systemctl", "--user", "show", "llm-beam10-oc-timing-supplemental-20261031.service", "-p", "ActiveState", "--value")
  raise "Prior review still active" unless status.success? && state.strip == "inactive"
  pids, status = Open3.capture2("pgrep", "-u", "llmtest")
  raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
  TimingAudit::AuditVerifier.new(old_root, "full").run
  selected = TimingAudit.load_jsonl(File.join(old_root, "supplemental-selection.jsonl"))
  halo = %w[stencil3d_beam-1.0-oc-medium_mpi_r1 stencil3d_beam-1.0-oc-medium_mpi_r3 unstructured_beam-1.0-oc-medium_mpi_r2]
  allgather = %w[nbody_beam-1.0-oc-medium_mpi_r1 nbody_beam-1.0-oc-medium_mpi_r5]
  decisions = TimingAudit.load_jsonl(File.join(primary, "final/decisions.jsonl")).to_h { |row| [row.fetch("program_id"), row] }
  (halo + allgather).each do |id|
    row = decisions.fetch(id)
    raise "Unexpected cross-check selection" unless row.fetch("final_verdict") == "valid" && row.fetch("decision_basis") == "sol_adjudication"
    selected << { "program_id" => id,
      "reason" => halo.include?(id) ?
        "Source-grounded consistency check: ordered Sendrecv completion is used to prove root-controlled start, but outgoing sends use already available data. Distinguish communication initiation from numerical-work gating." :
        "Source-grounded consistency check: initial Allgatherv completion is used to prove root-controlled start. Distinguish permitted input replication from any omitted intended timed communication; no verdict is prescribed." }
  end
  selection_path = File.join(campaign, "audit-supplemental-communication-selection-20261031.jsonl")
  raise "Selection already exists" if File.exist?(selection_path)
  TimingAudit.atomic_write(selection_path, TimingAudit.dump_jsonl(selected))
  context_path = File.join(campaign, "audit-supplemental-context-20261031.txt")
  TimingPriorityReview.prepare_supplemental(main_root: primary, output_dir: root,
    selection_path: selection_path, context_path: context_path, model: "gpt-6.1-sol")
  %w[prompt-template.txt result-schema.json runner-snapshot.rb platform-context.txt].each do |name|
    raise "Reuse artifact differs: #{name}" unless File.binread(File.join(root, name)) == File.binread(File.join(old_root, name))
  end
  runner = TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 1, model: "gpt-6.1-sol", effort: "xhigh")
  inventory = TimingAudit.load_jsonl(File.join(root, "inventory.jsonl")).to_h { |record| [record.fetch("id"), record] }
  old_inventory = TimingAudit.load_jsonl(File.join(old_root, "inventory.jsonl"))
  reused = []
  old_inventory.each do |record|
    id = record.fetch("id")
    raise "Reused inventory changed" unless inventory.fetch(id) == record
    result_path = File.join(old_root, "results", "#{id}.json")
    result_sha = TimingAudit.sha256_file(result_path)
    prompt_sha = TimingAudit.sha256_bytes(runner.send(:build_prompt, record))
    accepted = Dir[File.join(old_root, "logs", id, "attempt-*/metadata.yaml")].select do |path|
      metadata = YAML.safe_load_file(path)
      next false unless metadata["result_sha256"] == result_sha
      raise "Reused review request differs" unless metadata.fetch("prompt_sha256") == prompt_sha &&
        metadata.values_at("model", "reasoning_effort", "static_only_verified") == ["gpt-6.1-sol", "xhigh", true]
      true
    end
    raise "No exact accepted review to reuse" if accepted.empty?
    FileUtils.mkdir_p(File.join(root, "results"))
    FileUtils.mkdir_p(File.join(root, "logs"))
    FileUtils.cp(result_path, File.join(root, "results", "#{id}.json"))
    FileUtils.cp_r(File.join(old_root, "logs", id), File.join(root, "logs", id))
    TimingAudit::AuditVerifier.new(root, "full").verify_result!(id, JSON.parse(File.read(result_path)))
    reused << { "program_id" => id, "source_root" => old_root, "result_sha256" => result_sha,
      "prompt_sha256" => prompt_sha, "source_digest" => record.fetch("source_digest"), "new_model_requests" => 0 }
  end
  TimingAudit.atomic_write(File.join(root, "reused-reviews.json"), JSON.pretty_generate({ "created_at" => TimingAudit.utc_now,
    "source_manifest_sha256" => TimingAudit.sha256_file(File.join(old_root, "manifest.yaml")), "records" => reused }) + "\n")
  FileUtils.cp_r(File.join(old_root, "prior-final"), File.join(root, "prior-final"))
  FileUtils.mkdir_p(File.join(root, "reused-parent"))
  %w[manifest.yaml supplemental-selection.jsonl summary-full.jsonl summary-full.csv].each { |name| FileUtils.cp(File.join(old_root, name), File.join(root, "reused-parent", name)) }
  retained = old_receipt.fetch("retained_results").merge(Dir[File.join(old_root, "results/*.json")].to_h { |path| [path, TimingAudit.sha256_file(path)] })
  files = [__FILE__, selection_path, old_receipt_path, context_path, File.join(__dir__, "review-request-pacing.rb"), old_receipt.fetch("review_cli_path")]
  receipt = { "prepared_at" => TimingAudit.utc_now, "selected_ids" => selected.map { |r| r.fetch("program_id") }.sort,
    "new_review_ids" => (halo + allgather).sort, "reused_review_ids" => reused.map { |r| r.fetch("program_id") }.sort,
    "root" => root, "parent_root" => primary, "prior_gate_sha256" => old_receipt.fetch("prior_gate_sha256"),
    "files" => files.to_h { |path| [path, TimingAudit.sha256_file(path)] }, "retained_results" => retained,
    "prior_final" => Dir[File.join(root, "prior-final/*")].to_h { |path| [path, TimingAudit.sha256_file(path)] },
    "review_cli_path" => old_receipt.fetch("review_cli_path"), "review_cli_sha256" => old_receipt.fetch("review_cli_sha256"),
    "model" => "gpt-6.1-sol", "effort" => "xhigh", "workers" => 1, "minimum_request_spacing_seconds" => 90,
    "policy" => "Five targeted source-only consistency reviews, not a repeat of the audit. Reuse the two exact accepted focused requests, responses and raw evidence. Preserve every original decision; no execution or algorithmic correction." }
  TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
  FileUtils.cp(__FILE__, campaign)
  puts JSON.pretty_generate(receipt.reject { |k, _| %w[files retained_results prior_final].include?(k) })
  exit
end

receipt = JSON.parse(File.read(receipt_path))
%w[files retained_results prior_final].each do |key|
  receipt.fetch(key).each { |path, sha| raise "Retained input changed" unless TimingAudit.sha256_file(path) == sha }
end
ENV["PATH"] = "#{File.dirname(receipt.fetch('review_cli_path'))}:/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin"
BeamReviewPacing.next_request = Time.now
BeamReviewPacing.deadline = Time.iso8601("2026-11-06T17:00:00Z")
BeamReviewPacing.progress_path = File.join(campaign, "audit-supplemental-communication-20261031-progress.json")
BeamReviewPacing.recoveries = []
TimingAudit::AuditRunner.prepend(BeamReviewPacing::Dispatch)
begin
  TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 1, model: "gpt-6.1-sol", effort: "xhigh", retries: 1).run
  receipt.fetch("retained_results").each { |path, sha| raise "Accepted review changed" unless TimingAudit.sha256_file(path) == sha }
  BeamReviewPacing.checkpoint("awaiting_supplemental_quality_review")
rescue Exception => error
  BeamReviewPacing.checkpoint("stopped", "error" => "#{error.class}: #{error.message}")
  raise
end
