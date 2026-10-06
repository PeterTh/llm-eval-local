# frozen_string_literal: true

# Verifies recorded evidence only; never executes a generated program.
require "/tmp/opus55-evaluation-20261006.cnIZzu/experiment/lib/local_evaluation"

campaign = "/home/petert/llm_para_campaigns/20261002-142720-opus55-medium/evaluation"
original = "/home/petert/llm_para_local_evaluation/20261006-opus55-validation"
root = "/home/petert/llm_para_local_evaluation/20261006-opus55-corrected"
final = "/home/petert/llm_timing_fixes/20261006-opus55-final"
progress = JSON.parse(File.read(File.join(campaign, "revalidation-progress.json")))
raise "Revalidation not complete" unless progress.fetch("phase") == "complete"
manifest = LocalEvaluation::Manifest.new(root)
revision_report = manifest.verify_input_revisions!
pipeline = LocalEvaluation::ValidationPipeline.new(run_dir: root)
results = pipeline.send(:load_results)
ids = File.readlines(File.join(final, "correction-ids.txt"), chomp: true).sort
raise "Wrong correction coverage" unless results.keys.sort == ids && manifest.runs.keys.sort == ids && ids.size == 83
stages = %w[basic_para validation_build validation_run internal_validation output_comparison]
results.each do |id, result|
  raise "Native scientific validation failed: #{id}" unless stages.all? { |stage| result.public_send(stage) == true }
  raise "Native evidence inconsistent: #{id}" unless pipeline.send(:validation_artifacts_intact?, id, manifest.runs.fetch(id), result)
end
raise "Infrastructure error retained" unless Dir[File.join(root, "validation/**/infrastructure_error.log")].empty?
original_sha = LocalEvaluation.sha256_file(File.join(original, "validation/all_validation_results.yaml"))
raise "Original validation changed" unless original_sha == "c9e295c1a5efeb4fe324d91e9d8fc26e59520d48430abac73e45ec3b11a156d0"
decision = JSON.parse(File.read(File.join(campaign, "hash-policy-amendment/decision.json")))
decision.fetch("completed_record_files_sha256").each do |relative, digest|
  raise "Previously completed case changed: #{relative}" unless LocalEvaluation.sha256_file(File.join(root, relative)) == digest
end
comparison_path = File.join(final, "revalidation-numerical-comparison.json")
raise "Comparison report changed" unless LocalEvaluation.sha256_file(comparison_path) == progress.fetch("report_sha256")
comparison = JSON.parse(File.read(comparison_path))
raise "Wrong comparison coverage" unless comparison.fetch("comparisons").map { |row| row.fetch("program_id") }.sort == ids
corrected_sha = LocalEvaluation.sha256_file(File.join(root, "validation/all_validation_results.yaml"))
raise "Comparison report provenance mismatch" unless comparison.fetch("corrected_validation_sha256") == corrected_sha && comparison.fetch("original_validation_sha256") == original_sha
report = {
  "checked_at" => Time.now.utc.iso8601, "verification" => "passed",
  "checker_sha256" => LocalEvaluation.sha256_file(__FILE__),
  "completed" => results.size, "native_scientific_validation_passed" => results.size,
  "by_backend" => results.values.group_by(&:par_type).transform_values(&:size),
  "input_revisions" => revision_report, "manifest_sha256" => LocalEvaluation.sha256_file(manifest.path),
  "original_validation_sha256" => original_sha, "corrected_validation_sha256" => corrected_sha,
  "native_artifact_checks" => "passed for all 83 records", "infrastructure_errors" => [],
  "first_completed_case_preserved_without_retry" => true,
  "comparison_report_sha256" => LocalEvaluation.sha256_file(comparison_path),
  "cross_run_equality_is_informational_only" => true,
  "raw_results_differing_ids" => comparison.fetch("comparisons").reject { |row| row.fetch("numerical_results_identical") }.map { |row| row.fetch("program_id") },
  "non_hash_results_differing_ids" => comparison.fetch("comparisons").reject { |row| row.fetch("results_without_hash_identical") }.map { |row| row.fetch("program_id") }
}
output = File.join(campaign, "revalidation-completion-review.json")
raise "Completion verification already exists" if File.exist?(output)
LocalEvaluation.atomic_write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
