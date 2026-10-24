# frozen_string_literal: true

# Run only after completed native evidence has been exported. No generated
# programs, measurements, validation outcomes or historical inputs are changed.
require_relative "experiment/lib/local_evaluation"
require "open3"

scratch = __dir__
campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/evaluation"
run = "/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-validation"
corrected = "/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-corrected"
batch = File.join(scratch, "release/batches/20261019-134042")
receipt_path = File.join(campaign, "aggregate-export-amendment.json")
raise "Aggregate export amendment already applied" if File.exist?(receipt_path)
completion = JSON.parse(File.read(File.join(campaign, "benchmark-completion-review.json")))
raise "Benchmark evidence incomplete" unless completion.fetch("verification") == "passed" && completion.fetch("completed") == 218
raise "Export native evidence before amending aggregation" unless File.file?(File.join(batch, "benchmark/summary.json"))
state, status = Open3.capture2("systemctl", "--user", "show", "llm-deepseek41-oc-benchmark-20261023.service", "--property=ActiveState", "--value")
raise "Benchmark service active" unless status.success? && !%w[active activating deactivating].include?(state.strip)
lock = LocalEvaluation::RunLock.new(run)
host_lock = LocalEvaluation::HostPerformanceLock.new
begin
  manifest = LocalEvaluation::Manifest.new(run)
  manifest.verify_input_revisions!(operation: "aggregate")
  raise "Unexpected existing pipeline amendment" unless LocalEvaluation::PipelineAmendment.paths_for(run).empty?
  tracked = [File.join(run, "validation/all_validation_results.yaml"), File.join(corrected, "validation/all_validation_results.yaml"),
    File.join(run, "benchmark/benchmark_full_results.yaml"), File.join(run, "benchmark/benchmark_run_metadata.yaml"),
    *Dir[File.join(run, "benchmark/*/benchmark_metadata.yaml")]].sort
  before = tracked.to_h { |path| [path, LocalEvaluation.sha256_file(path)] }
  commit = "d999115c68d842a1ef1d15150780fff78953312c"
  relative = "lib/local_evaluation/aggregate_pipeline.rb"
  bytes, status = Open3.capture2("git", "-C", "/home/petert/llm_eval/experiment", "show", "#{commit}:#{relative}")
  raise "Committed CSV export fix unavailable" unless status.success?
  pipeline_root = manifest.data.fetch("pipeline_source").fetch("root")
  raise "Unexpected measurement pipeline root" unless pipeline_root == File.join(scratch, "experiment")
  target = File.join(pipeline_root, relative)
  old_digest = LocalEvaluation.sha256_file(target)
  raise "Frozen aggregate source changed" unless old_digest == manifest.data.fetch("pipeline_source").fetch("files").fetch(relative)
  LocalEvaluation.atomic_write(target, bytes)
  reason = "Metadata-only CSV export: retain generation outcome, explicit usage completeness, partial completed-request counters and model-termination evidence digests. Complete token/cost fields remain unavailable for interrupted sessions. No validation, benchmark, sizes, resource limits, measurements or retry policy changed; no execution is requested."
  preview = LocalEvaluation::PipelineAmendment.create!(manifest: manifest, affected_ids: manifest.runs.keys, reason: reason, dry_run: true)
  raise "Amendment touches native execution" unless preview.fetch("changed_files").keys == [relative]
  amendment = LocalEvaluation::PipelineAmendment.create!(manifest: manifest, affected_ids: manifest.runs.keys, reason: reason)
  after = tracked.to_h { |path| [path, LocalEvaluation.sha256_file(path)] }
  raise "Scientific results changed" unless after == before
  [amendment.path, "#{amendment.path}.sha256"].each do |path|
    FileUtils.cp(path, File.join(batch, "benchmark/provenance", File.basename(path)))
  end
  receipt = {
    "applied_at" => Time.now.utc.iso8601, "source_commit" => commit,
    "amendment_path" => amendment.path, "amendment_sha256" => amendment.digest,
    "changed_files" => amendment.data.fetch("changed_files"),
    "old_pipeline_sha256" => amendment.data.fetch("original_pipeline_source_sha256"),
    "new_pipeline_sha256" => amendment.data.fetch("amended_pipeline_source").fetch("sha256"),
    "scientific_evidence_unchanged" => true, "guarded_file_count" => before.size,
    "guard_sha256" => Digest::SHA256.hexdigest(JSON.generate(before)),
    "tests" => { "opencode_generation" => { "runs" => 29, "assertions" => 175, "failures" => 0, "errors" => 0 },
      "local_evaluation" => { "runs" => 24, "assertions" => 143, "failures" => 0, "errors" => 0 } },
    "driver_sha256" => LocalEvaluation.sha256_file(__FILE__), "policy" => reason
  }
  LocalEvaluation.atomic_write(receipt_path, JSON.pretty_generate(receipt) + "\n")
  FileUtils.cp(__FILE__, campaign)
  puts JSON.pretty_generate(receipt)
ensure
  host_lock&.close
  lock&.close
end
