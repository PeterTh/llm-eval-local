#!/usr/bin/env ruby
# frozen_string_literal: true

require "/home/petert/llm_eval/experiment/tools/timing_audit/bin/benchmark_validation_batch"

$stdout.sync = true
run_dir = "/home/petert/llm_para_local_evaluation/20260928-claude5-validation"
retry_dir = File.join(run_dir, "benchmark-campaign/file-limit-retry")
ids = %w[cholesky_claude-opus-5-cc-medium_mpi_r4 matmul_claude-opus-5-cc-medium_hybrid_r2 matmul_claude-opus-5-cc-medium_mpi_r4]
run_lock = LocalEvaluation::RunLock.new(run_dir)
host_lock = LocalEvaluation::HostPerformanceLock.new
manifest = LocalEvaluation::Manifest.new(run_dir)
campaign = BenchmarkValidationBatch.campaign_data(run_dir)
source = campaign.dig("original_source", "path")
original_commit = campaign.dig("original_source", "commit")
corrected_commit = campaign.fetch("corrected_source_commit")
checkout_changed = false
checkpoint = lambda do |phase, extra = {}|
  LocalEvaluation.atomic_yaml(File.join(retry_dir, "progress.yaml"),
    { "updated_at" => Time.now.iso8601, "phase" => phase, "pid" => Process.pid }.merge(extra))
end

begin
  raise "Retry already prepared; inspect its state before resuming" if File.exist?(retry_dir)
  TimingAudit::SourceRepository.new(root: source, commit: corrected_commit)
  manifest.verify_non_pipeline_input_revisions!
  changes = LocalEvaluation::PipelineAmendment.send(:changed_file_map,
    manifest.data.fetch("pipeline_source").fetch("files"), LocalEvaluation.pipeline_source_snapshot.fetch("files"))
  raise "Unexpected pipeline changes" unless changes.keys == ["lib/local_evaluation/support.rb"]
  raise "Unexpected file-size policy" unless LocalEvaluation::ExecutionLimits::VALIDATION.fetch(:file_size_max_bytes) == 1024**3 &&
    LocalEvaluation::ExecutionLimits::PERFORMANCE.fetch(:file_size_max_bytes) == 1024**3
  results = BenchmarkValidationBatch.full_results(run_dir)
  raise "Unexpected completed corpus" unless results.size == 642
  ids.each do |id|
    raise "Selected result is not a failure" unless results.fetch(id) == [false, {}]
    stderr = File.read(File.join(run_dir, "benchmark", id, "benchmark_warmup_stderr.log"))
    raise "Selected failure is not SIGXFSZ" unless stderr.include?("signal 25 (File size limit exceeded)")
  end
  unaffected = results.keys.sort - ids
  guard = BenchmarkValidationBatch.verify_partition!(run_dir, unaffected)
  correction = LocalEvaluation::SourceCorrectionAmendment.load(run_dir, manifest: manifest)
  original_ids = ids - correction.affected_ids
  corrected_ids = ids & correction.affected_ids
  original_ids.each do |id|
    prefix = "#{manifest.runs.fetch(id).fetch('batch')}/#{id}"
    trees = TimingAudit.capture!("git", "-C", source, "rev-parse", "#{original_commit}:#{prefix}", "#{corrected_commit}:#{prefix}").lines(chomp: true)
    raise "Uncorrected source differs between commits" unless trees.size == 2 && trees.uniq.size == 1
  end
  amendment = LocalEvaluation::PipelineAmendment.create!(manifest: manifest, affected_ids: ids,
    reason: "User-approved uniform increase of validation/performance RLIMIT_FSIZE from 64 MiB to 1 GiB to accommodate standard MPI shared-memory backing files. Retry only the three SIGXFSZ failures, with identical sources, benchmark sizes, iterations, rank placement, warmup, repetitions and all other limits. Historical local results showed no affected cases.")
  raise "Unexpected amendment scope" unless amendment.data.fetch("affected_run_ids") == ids
  LocalEvaluation.atomic_yaml_with_digest(File.join(retry_dir, "unaffected-guard.yaml"), guard, immutable: true)
  LocalEvaluation.atomic_write(File.join(retry_dir, "ids.txt"), ids.join("\n") + "\n", mode: 0o444)
  LocalEvaluation.atomic_write(File.join(retry_dir, "runner.rb"), File.binread(__FILE__), mode: 0o444)
  support = File.join(manifest.data.dig("pipeline_source", "root"), "lib/local_evaluation/support.rb")
  LocalEvaluation.atomic_write(File.join(retry_dir, "support.rb"), File.binread(support), mode: 0o444)
  retry_manifest = {
    "schema_version" => 1, "created_at" => Time.now.iso8601, "affected_run_ids" => ids,
    "pipeline_amendment_sha256" => amendment.digest,
    "configuration_sha256" => campaign.fetch("configuration_sha256"),
    "original_source_commit" => original_commit, "corrected_source_commit" => corrected_commit,
    "previous_file_size_max_bytes" => 64 * 1024**2, "file_size_max_bytes" => 1024**3,
    "unaffected_count" => unaffected.size, "unaffected_guard_sha256" => LocalEvaluation.sha256_file(File.join(retry_dir, "unaffected-guard.yaml")),
    "superseded_metadata_sha256" => ids.to_h { |id| [id, LocalEvaluation.sha256_file(File.join(run_dir, "benchmark", id, "benchmark_metadata.yaml"))] },
    "prior_invocations" => LocalEvaluation.load_yaml(File.join(run_dir, "benchmark/benchmark_run_metadata.yaml")).fetch("invocations"),
    "artifacts" => %w[runner.rb support.rb ids.txt].to_h { |name| [name, LocalEvaluation.sha256_file(File.join(retry_dir, name))] }
  }
  LocalEvaluation.atomic_yaml_with_digest(File.join(retry_dir, "manifest.yaml"), retry_manifest, immutable: true)
  [[original_commit, original_ids], [corrected_commit, corrected_ids]].each do |commit, selected|
    next if selected.empty?
    # Use the original clean checkout for unchanged sources, and the accepted
    # corrected checkout for corrected sources; both existing authorization
    # mechanisms therefore remain intact without weakening source guards.
    TimingAudit.capture!("git", "-C", source, "checkout", "--quiet", "--detach", commit)
    checkout_changed = true
    TimingAudit::SourceRepository.new(root: source, commit: commit)
    checkpoint.call("benchmark", "selected_ids" => selected, "source_commit" => commit)
    manifest.verify_input_revisions!(operation: "benchmark", selected_ids: selected)
    LocalEvaluation::BenchmarkPipeline.new(run_dir: run_dir, ids: selected, retry_failed: true).run
  end
  raise "Unrelated records changed" unless BenchmarkValidationBatch.verify_partition!(run_dir, unaffected) == guard
  BenchmarkValidationBatch.verify_partition!(run_dir, ids)
  results = BenchmarkValidationBatch.full_results(run_dir)
  raise "Final ID set differs" unless results.keys.sort == (unaffected + ids).sort
  ids.each do |id|
    previous = Dir[File.join(run_dir, "benchmark/attempts", id, "*", "benchmark_metadata.yaml")]
      .select { |path| LocalEvaluation.sha256_file(path) == retry_manifest.fetch("superseded_metadata_sha256").fetch(id) }
    raise "Original attempt not preserved" unless previous.size == 1
  end
  checkpoint.call("complete", "affected_results" => ids.to_h { |id| [id, results.fetch(id).first] },
    "successful" => results.count { |_id, record| record.first == true },
    "failed" => results.count { |_id, record| record.first == false },
    "unaffected_records_verified" => unaffected.size, "configuration_unchanged" => true)
  puts "Scoped retry complete; #{unaffected.size} unrelated records verified unchanged"
rescue Exception => error
  checkpoint.call("stopped", "error" => "#{error.class}: #{error.message}") if File.directory?(retry_dir)
  raise
ensure
  if checkout_changed && TimingAudit.capture!("git", "-C", source, "rev-parse", "HEAD").strip != corrected_commit
    TimingAudit.capture!("git", "-C", source, "checkout", "--quiet", "--detach", corrected_commit)
  end
  host_lock&.close
  run_lock&.close
end
