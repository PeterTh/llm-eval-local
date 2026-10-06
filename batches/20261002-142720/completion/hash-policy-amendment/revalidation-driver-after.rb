# frozen_string_literal: true

$stdout.sync = true
require "/tmp/opus55-evaluation-20261006.cnIZzu/experiment/lib/local_evaluation"

campaign = "/home/petert/llm_para_campaigns/20261002-142720-opus55-medium/evaluation"
original = "/home/petert/llm_para_local_evaluation/20261006-opus55-validation"
corrected = "/home/petert/llm_para_local_evaluation/20261006-opus55-corrected"
final = "/home/petert/llm_timing_fixes/20261006-opus55-final"
source = "/tmp/opus55-evaluation-20261006.cnIZzu/corrected"
reference = "/tmp/opus55-evaluation-20261006.cnIZzu/benchmarks"
original_results_sha = "c9e295c1a5efeb4fe324d91e9d8fc26e59520d48430abac73e45ec3b11a156d0"
phase = "verify_corrections"
active_id = nil
checkpoint = lambda do |extra = {}|
  LocalEvaluation.atomic_write(File.join(campaign, "revalidation-progress.json"), JSON.pretty_generate({
    "updated_at" => Time.now.utc.iso8601, "pid" => Process.pid, "phase" => phase,
    "active_id" => active_id, "driver_sha256" => LocalEvaluation.sha256_file(__FILE__)
  }.merge(extra)) + "\n")
end

begin
  checkpoint.call
  evidence = LocalEvaluation.load_yaml(File.join(final, "manifest.yaml"))
  ids_path = File.join(final, "correction-ids.txt")
  raise "Correction ID list changed" unless LocalEvaluation.sha256_file(ids_path) == evidence.dig("artifacts", "correction_ids_sha256")
  ids = File.readlines(ids_path, chomp: true).reject(&:empty?).sort
  raise "Unexpected correction set" unless ids.size == evidence.fetch("record_count") && ids.uniq == ids && !ids.empty?
  raise "Original validation changed" unless LocalEvaluation.sha256_file(File.join(original, "validation/all_validation_results.yaml")) == original_results_sha
  FileUtils.mkdir_p(corrected)
  run_lock = LocalEvaluation::RunLock.new(corrected)
  host_lock = LocalEvaluation::HostPerformanceLock.new
  manifest_path = File.join(corrected, "evaluation_manifest.yaml")
  manifest = if File.file?(manifest_path)
    LocalEvaluation::Manifest.new(corrected)
  else
    LocalEvaluation::Manifest.create(experiments_root: source, run_dir: corrected, benchmarks_root: reference)
  end
  original_manifest = LocalEvaluation::Manifest.new(original)
  raise "Revalidation must cover exactly the corrections" unless manifest.runs.keys.sort == ids
  raise "Wrong corrected source revision" unless manifest.data.dig("experiment_repository", "commit") == evidence.dig("corrected_source", "commit")
  %w[pipeline_source benchmark_repository resource_profiles].each do |key|
    raise "Revalidation changed #{key}" unless manifest.data.fetch(key) == original_manifest.data.fetch(key)
  end
  manifest.verify_input_revisions!
  comparisons = []
  ids.each_with_index do |id, index|
    active_id = id
    phase = "revalidate_corrected"
    checkpoint.call("completed" => index, "expected" => ids.size)
    pipeline = LocalEvaluation::ValidationPipeline.new(run_dir: corrected, exact_id: id)
    pipeline.run
    result = pipeline.send(:load_results).fetch(id)
    raise "Native validation artifacts inconsistent for #{id}" unless pipeline.send(:validation_artifacts_intact?, id, manifest.runs.fetch(id), result)
    stages = %w[basic_para validation_build validation_run internal_validation output_comparison]
    unless stages.all? { |stage| result.public_send(stage) == true }
      raise "Corrected validation failed for #{id}: #{result.err_string}; preserve without retry and investigate"
    end
    logs = [original, corrected].map { |root| File.join(root, "validation", id, "validation_out_stdout.log") }
    blocks = logs.map { |path| File.binread(path).scan(/=== RESULTS ===.*?=== END RESULTS ===/m) }
    raise "Missing numerical RESULTS block for #{id}" if blocks.any?(&:empty?)
    without_hash = blocks.map { |set| set.map { |block| block.lines.reject { |line| line.lstrip.start_with?("Hash: ") }.join } }
    comparisons << {
      "program_id" => id, "numerical_results_identical" => blocks[0] == blocks[1],
      "results_without_hash_identical" => without_hash[0] == without_hash[1],
      "original_stdout_sha256" => LocalEvaluation.sha256_file(logs[0]),
      "corrected_stdout_sha256" => LocalEvaluation.sha256_file(logs[1]),
      "original_numerical_results_sha256" => Digest::SHA256.hexdigest(JSON.generate(blocks[0])),
      "corrected_numerical_results_sha256" => Digest::SHA256.hexdigest(JSON.generate(blocks[1]))
    }
    # Native scientific validation above is the acceptance criterion. Cross-run
    # byte equality is descriptive evidence, not an additional validation gate;
    # the native validator explicitly does not require equal result hashes.
  end
  raise "Original validation changed" unless LocalEvaluation.sha256_file(File.join(original, "validation/all_validation_results.yaml")) == original_results_sha
  phase = "complete"
  active_id = nil
  report = {
    "checked_at" => Time.now.utc.iso8601, "records" => comparisons.size,
    "all_numerical_results_identical" => comparisons.all? { |row| row.fetch("numerical_results_identical") },
    "all_results_without_hash_identical" => comparisons.all? { |row| row.fetch("results_without_hash_identical") },
    "comparison_role" => "informational_only; unchanged native scientific validation determines acceptance",
    "hash_policy" => "Result Hash differences ignored where not required by the native validator; user decision 2026-10-06",
    "comparisons" => comparisons,
    "original_validation_sha256" => original_results_sha,
    "corrected_manifest_sha256" => LocalEvaluation.sha256_file(manifest.path),
    "corrected_validation_sha256" => LocalEvaluation.sha256_file(File.join(corrected, "validation/all_validation_results.yaml")),
    "original_source_commit" => evidence.dig("original_source", "commit"),
    "corrected_source_commit" => evidence.dig("corrected_source", "commit"),
    "retries_requested" => false, "native_artifact_checks" => "passed for every corrected record"
  }
  output = File.join(final, "revalidation-numerical-comparison.json")
  raise "Completion report already exists" if File.exist?(output)
  LocalEvaluation.atomic_write(output, JSON.pretty_generate(report) + "\n")
  checkpoint.call("completed" => ids.size, "expected" => ids.size, "report_sha256" => LocalEvaluation.sha256_file(output))
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
ensure
  host_lock&.close
  run_lock&.close
end
