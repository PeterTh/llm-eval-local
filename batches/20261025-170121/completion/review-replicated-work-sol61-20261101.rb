# frozen_string_literal: true
$stdout.sync = true
require "open3"
require_relative "experiment/tools/timing_audit/lib/timing_audit"
require_relative "review-request-pacing"
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
prior = primary + "-replicated-work-luna-20261101"
extra = primary + "-replicated-work-extra-luna-20261101"
root = primary + "-replicated-work-sol61-20261101"
receipt_path = File.join(campaign, "replicated-work-sol61-review-launch-20261101.json")
ids = %w[roomsim_beam-1.0-oc-medium_hybrid_r5]
mode = ARGV.fetch(0)
raise "Use prepare|run" unless ARGV.size == 1 && %w[prepare run].include?(mode)
if mode == "prepare"
  raise "Adjudication already prepared" if File.exist?(root) || File.exist?(receipt_path)
  reference = File.join(__dir__, "benchmarks/roomsim/roomsim.cpp")
  reference_commit, status = Open3.capture2("git", "-C", File.join(__dir__, "benchmarks"), "rev-parse", "HEAD")
  raise "Unexpected reference revision" unless status.success? && reference_commit.strip == "2bc11aeac658a87b5cae25d03e0669f65d32922e"
  reference_sha = TimingAudit.sha256_file(reference)
  selection = ids.map { |id| { "program_id" => id, "reason" => "The focused Luna review accepts independent full-result ownership but flags octree/triangle-area initialization outside timing. The sequential reference itself calls initializeSimulation before its timed phases. Adjudicate against the exact unchanged reference boundary, without requiring extra work that was already outside that boundary. Check independently whether the implementation moves any reference-timed work out of the reported interval." } }
  TimingAudit.derive_inventory(parent_root: primary, output_dir: root, ids: ids, provenance: {
    "supplemental_adjudication" => { "model" => "gpt-6.1-sol", "effort" => "xhigh", "records" => ids.size, "selection" => selection },
    "reference_boundary" => { "commit" => reference_commit.strip, "path" => "roomsim/roomsim.cpp", "sha256" => reference_sha }
  })
  TimingAudit.atomic_write(File.join(root, "supplemental-selection.jsonl"), TimingAudit.dump_jsonl(selection))
  TimingAudit.atomic_write(File.join(root, "sequential-reference.cpp"), File.binread(reference))
  # Escape reference percent signs only in the format template, not the retained source.
  numbered_reference = File.readlines(reference).each_with_index.map { |line, i| "%5d  %s" % [i + 1, line] }.join.gsub("%", "%%")
  context = <<~TEXT
    SEQUENTIAL REFERENCE TIMING BOUNDARY

    The experiment measures the computation region defined by the unchanged
    sequential reference below, including replacements for work within that region.
    Initialization that is already outside the reference timer is not newly required
    inside an implementation's timer. For RoomSim, distinguish initializeSimulation
    from the timed time-delay/form-factor, propagation, and distance phases. Identify
    any actual movement of reference-timed work out of the generated timer rather
    than expanding the experimental metric to all possible preprocessing.
    The independent complete-result replica clarification in this prompt still applies.
    No code execution, compilation, shell commands, or tools are permitted.
    Cite generated source evidence in the structured evidence array; discuss the
    separately numbered sequential reference in notes as needed.

    Reference commit: #{reference_commit.strip}
    Reference SHA-256: #{reference_sha}
    Reference file: roomsim/roomsim.cpp

    #{numbered_reference}

  TEXT
  original_prompt = File.read(File.join(prior, "prompt-template.txt"))
  prompt = original_prompt.sub("SOURCE DOSSIER\n") { context + "SOURCE DOSSIER\n" }
  raise "Reference context insertion failed" if prompt == original_prompt
  manifest_path = File.join(root, "manifest.yaml")
  manifest = YAML.safe_load_file(manifest_path)
  %w[result-schema.json runner-snapshot.rb platform-context.txt review-guidance.txt replicated-work-timing-contract.txt].each do |name|
    TimingAudit.atomic_write(File.join(root, name), File.binread(File.join(prior, name)))
  end
  TimingAudit.atomic_write(File.join(root, "prompt-template.txt"), prompt)
  { "prompt_template_sha256" => "prompt-template.txt", "result_schema_sha256" => "result-schema.json", "runner_sha256" => "runner-snapshot.rb" }.each do |key, name|
    manifest.fetch("artifacts")[key] = TimingAudit.sha256_file(File.join(root, name))
  end
  TimingAudit.atomic_write(manifest_path, YAML.dump(manifest))
  parent = JSON.parse(File.read(File.join(campaign, "replicated-work-review-launch-20261101.json")))
  files = [__FILE__, reference, File.join(__dir__, "review-request-pacing.rb"), *Dir[File.join(root, "*")].select { |path| File.file?(path) }, *Dir[File.join(prior, "results/*.json")], *Dir[File.join(extra, "results/*.json")]]
  receipt = { "prepared_at" => TimingAudit.utc_now, "root" => root, "selected_ids" => ids,
    "files" => files.to_h { |path| [path, TimingAudit.sha256_file(path)] },
    "review_cli_path" => parent.fetch("review_cli_path"), "review_cli_sha256" => parent.fetch("review_cli_sha256"),
    "model" => "gpt-6.1-sol", "effort" => "xhigh", "workers" => 1, "minimum_request_spacing_seconds" => 90,
    "source_only" => true, "program_execution_allowed" => false, "new_reviews" => ids.size }
  TimingAudit.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
  FileUtils.cp(__FILE__, campaign)
  puts JSON.pretty_generate(receipt.except("files"))
  exit
end
receipt = JSON.parse(File.read(receipt_path))
receipt.fetch("files").each { |path, sha| raise "Adjudication input changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
raise "Pinned CLI changed" unless TimingAudit.sha256_file(receipt.fetch("review_cli_path")) == receipt.fetch("review_cli_sha256")
%w[llm-beam10-oc-replicated-work-20261101.service llm-beam10-oc-replicated-work-extra-20261101.service].each do |unit|
  state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
  raise "Another focused review is active" unless status.success? && state.strip == "inactive"
end
previous = JSON.parse(File.read(File.join(campaign, "replicated-work-extra-review-progress-20261101.json")))
raise "Focused Luna checks incomplete" unless previous.fetch("phase") == "awaiting_replicated_work_review"
ENV["PATH"] = "#{File.dirname(receipt.fetch('review_cli_path'))}:/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin"
BeamReviewPacing.next_request = [Time.now, Time.iso8601(previous.fetch("next_request_not_before"))].max
BeamReviewPacing.deadline = Time.iso8601("2026-11-06T17:00:00Z")
BeamReviewPacing.progress_path = File.join(campaign, "replicated-work-sol61-review-progress-20261101.json")
BeamReviewPacing.recoveries = []
TimingAudit::AuditRunner.prepend(BeamReviewPacing::Dispatch)
begin
  TimingAudit::AuditRunner.new(output_dir: root, scope: "full", jobs: 1, model: "gpt-6.1-sol", effort: "xhigh", retries: 1).run
  BeamReviewPacing.checkpoint("awaiting_replicated_work_review")
rescue Exception => error
  BeamReviewPacing.checkpoint("stopped", "error" => "#{error.class}: #{error.message}")
  raise
end
