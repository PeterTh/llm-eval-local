# frozen_string_literal: true
$stdout.sync = true
require "open3"
require_relative "experiment/tools/timing_audit/bin/timing_priority_review"
require_relative "review-request-pacing"

campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
root = primary + "-replicated-work-luna-20261101"
receipt_path = File.join(campaign, "replicated-work-review-launch-20261101.json")
ids = %w[floydwarshall_beam-1.0-oc-medium_hybrid_r3 qtclustering_beam-1.0-oc-medium_hybrid_r1 roomsim_beam-1.0-oc-medium_hybrid_r1 roomsim_beam-1.0-oc-medium_hybrid_r5 unstructured_beam-1.0-oc-medium_hybrid_r4]
mode = ARGV.fetch(0)
raise "Use prepare|run" unless ARGV.size == 1 && %w[prepare run].include?(mode)

if mode == "prepare"
  raise "Focused review already prepared" if File.exist?(root) || File.exist?(receipt_path)
  pids, status = Open3.capture2("pgrep", "-u", "llmtest")
  raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
  %w[llm-fable51-generation-20261011-092100.service llm-beam10-oc-correction-full-20261031.service].each do |unit|
    state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
    raise "Competing campaign active" unless status.success? && state.strip == "inactive"
  end
  hold = File.join(campaign, "correction-build-scope-review-20261101.json")
  old = JSON.parse(File.read(hold))
  old.fetch("proposal_sha256").each do |name, sha|
    path = File.join("/home/petert/llm_timing_fixes/20261030-beam10-opencode-proposals/proposals", name)
    raise "Retained proposal changed" unless TimingAudit.sha256_file(path) == sha
  end
  policy_source = "/home/petert/llm_eval/experiment/tools/timing_audit/prompts/replicated_work_timing_contract.txt"
  policy = File.read(policy_source)
  authorization = {
    "recorded_at" => TimingAudit.utc_now,
    "user_statement" => "I don't think there is a requirement to do timing correction for this then: the result is available one any process completes, so local timing is valid in this case.",
    "explicit_case" => "cahn-hilliard_beam-1.0-oc-medium_hybrid_r5",
    "source_commit" => "74652eee82e2473660a7e75f3ad5d77fd0e3759c",
    "source_digest" => "8cc413026838627e4745e1c268885782eca5784bd19b0cedd167677fc3be5485",
    "decision" => "valid local timing of independently completed full result; no timing correction",
    "policy_sha256" => TimingAudit.sha256_bytes(policy),
    "same_batch_consistency_candidates" => ids,
    "scope" => "Targeted source-only consistency check under the user's complete-result criterion, not a new execution or a blanket exemption for local timings. Original reviews and sources remain unchanged."
  }
  policy_path = File.join(campaign, "replicated-work-timing-contract-20261101.txt")
  authorization_path = File.join(campaign, "replicated-work-user-decision-20261101.json")
  raise "Decision already retained" if File.exist?(authorization_path) || File.exist?(policy_path)
  TimingAudit.atomic_write(policy_path, policy)
  TimingAudit.atomic_write(authorization_path, JSON.pretty_generate(authorization) + "\n")
  selection_path = File.join(campaign, "replicated-work-selection-20261101.jsonl")
  selection = ids.map { |id| { "program_id" => id, "reason" => "Existing audit findings describe possibly redundant full-result computation. Independently verify the actual source under the clarified complete-result criterion, including complete local timing and device completion; no verdict is prescribed." } }
  TimingAudit.atomic_write(selection_path, TimingAudit.dump_jsonl(selection))
  context = File.join(__dir__, "timing-platform-context.txt")
  TimingPriorityReview.prepare_supplemental(main_root: primary, output_dir: root, selection_path: selection_path, context_path: context, model: "gpt-5.6-luna")
  # This is a new immutable request family, prepared before its first model call.
  # Parent requests and responses are retained; no earlier snapshot is changed.
  prompt_path = File.join(root, "prompt-template.txt")
  prior_prompt = File.read(prompt_path)
  marker = "TIMING CONTRACT\n"
  raise "Contract marker missing" unless prior_prompt.include?(marker)
  prompt = prior_prompt.sub(marker, marker + "\nThe following user-approved clarification qualifies the distributed-rank rules below.\n\n" + policy + "\nDISTRIBUTED-RANK RULES (WHEN RANKS COOPERATE TO PRODUCE A COMPLETE RESULT)\n")
  manifest_path = File.join(root, "manifest.yaml")
  manifest = YAML.safe_load_file(manifest_path)
  manifest.fetch("supplemental_adjudication")["effort"] = "high"
  manifest["user_contract_clarification"] = authorization.merge("authorization_sha256" => TimingAudit.sha256_file(authorization_path), "parent_prompt_sha256" => TimingAudit.sha256_bytes(prior_prompt))
  TimingAudit.atomic_write(File.join(root, "parent-prompt-template.txt"), prior_prompt)
  TimingAudit.atomic_write(File.join(root, "replicated-work-timing-contract.txt"), policy)
  TimingAudit.atomic_write(prompt_path, prompt)
  manifest.fetch("artifacts")["prompt_template_sha256"] = TimingAudit.sha256_bytes(prompt)
  TimingAudit.atomic_write(manifest_path, YAML.dump(manifest))
  cli = JSON.parse(File.read(File.join(campaign, "audit-pilot-launch.json")))
  raise "Pinned CLI changed" unless TimingAudit.sha256_file(cli.fetch("review_cli_path")) == cli.fetch("review_cli_sha256")
  paths = [__FILE__, policy_path, authorization_path, selection_path, context, hold, File.join(__dir__, "review-request-pacing.rb"), cli.fetch("review_cli_path"), *Dir[File.join(root, "*")].select { |path| File.file?(path) }]
  retained = Dir[primary + "{,-priority,-sol61,-qtclustering,-qtclustering-sol61,-supplemental-communication-20261031}/results/*.json"].sort.to_h { |path| [path, TimingAudit.sha256_file(path)] }
  receipt = { "prepared_at" => TimingAudit.utc_now, "root" => root, "selected_ids" => ids,
    "files" => paths.uniq.to_h { |path| [path, TimingAudit.sha256_file(path)] }, "retained_responses" => retained,
    "review_cli_path" => cli.fetch("review_cli_path"), "review_cli_sha256" => cli.fetch("review_cli_sha256"),
    "model" => "gpt-5.6-luna", "effort" => "high", "workers" => 1, "minimum_request_spacing_seconds" => 90,
    "stronger_review_policy" => "Sol6.1 only if this focused review remains uncertain; old verdicts under the superseded maximum-for-all-processes interpretation are not same-policy disagreements.",
    "source_only" => true, "program_execution_allowed" => false }
  TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
  FileUtils.cp(__FILE__, campaign)
  puts JSON.pretty_generate(receipt.reject { |key, _| %w[files retained_responses].include?(key) })
  exit
end

receipt = JSON.parse(File.read(receipt_path))
%w[files retained_responses].each { |key| receipt.fetch(key).each { |path, sha| raise "Focused-review evidence changed: #{path}" unless TimingAudit.sha256_file(path) == sha } }
ENV["PATH"] = "#{File.dirname(receipt.fetch('review_cli_path'))}:/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin"
BeamReviewPacing.next_request = Time.now
BeamReviewPacing.deadline = Time.iso8601("2026-11-06T17:00:00Z")
BeamReviewPacing.progress_path = File.join(campaign, "replicated-work-review-progress-20261101.json")
BeamReviewPacing.recoveries = []
TimingAudit::AuditRunner.prepend(BeamReviewPacing::Dispatch)
begin
  TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 1, model: "gpt-5.6-luna", effort: "high", retries: 1).run
  receipt.fetch("retained_responses").each { |path, sha| raise "Earlier response changed" unless TimingAudit.sha256_file(path) == sha }
  BeamReviewPacing.checkpoint("awaiting_replicated_work_review")
rescue Exception => error
  BeamReviewPacing.checkpoint("stopped", "error" => "#{error.class}: #{error.message}")
  raise
end
