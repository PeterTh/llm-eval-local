# frozen_string_literal: true

require "/tmp/sol61-evaluation-20261010.xL0RJx/experiment/lib/local_evaluation"

root = "/home/petert/llm_para_local_evaluation/20261010-sol61-validation"
manifest = LocalEvaluation::Manifest.new(root)
revision_report = manifest.verify_input_revisions!
pipeline = LocalEvaluation::ValidationPipeline.new(run_dir: root)
results = pipeline.send(:load_results)
raise "Validation is not complete" unless results.keys.sort == manifest.runs.keys.sort && results.size == 440
results.each do |id, result|
  raise "Incomplete or inconsistent artifacts for #{id}" unless
    pipeline.send(:validation_artifacts_intact?, id, manifest.runs.fetch(id), result)
end
infrastructure_errors = Dir[File.join(root, "validation", "**", "infrastructure_error.log")]
raise "Infrastructure failures require investigation" unless infrastructure_errors.empty?
stages = %w[basic_para validation_build validation_run internal_validation output_comparison]
report = {
  "checked_at" => Time.now.utc.iso8601,
  "batch" => "20261006-204623",
  "source_commit" => manifest.data.fetch("experiment_repository").fetch("commit"),
  "manifest_sha256" => LocalEvaluation.sha256_file(manifest.path),
  "validation_results_sha256" => LocalEvaluation.sha256_file(File.join(root, "validation/all_validation_results.yaml")),
  "input_revisions" => revision_report, "completed" => results.size,
  "passed" => results.values.count(&:output_comparison),
  "by_model" => results.values.group_by(&:model).transform_values { |rows|
    { "completed" => rows.size, "passed" => rows.count(&:output_comparison) }
  },
  "by_backend" => results.values.group_by(&:par_type).transform_values { |rows|
    { "completed" => rows.size, "passed" => rows.count(&:output_comparison) }
  },
  "stage_counts" => stages.to_h { |stage| [stage, results.values.count { |row| row.public_send(stage) }] },
  "failures" => results.values.reject(&:output_comparison).map { |row|
    { "program_id" => row.id_string, "failed_stage" => stages.find { |stage| !row.public_send(stage) }, "error" => row.err_string }
  },
  "passing_mpi_hybrid" => results.values.count { |row| row.output_comparison && %w[mpi hybrid].include?(row.par_type) },
  "passing_qtclustering" => results.values.count { |row| row.output_comparison && row.benchmark == "qtclustering" },
  "native_artifact_checks" => "passed for all 440 records", "infrastructure_errors" => [],
  "retries_requested" => false, "timing_review_started" => false, "benchmarking_started" => false
}
output = File.join(root, "validation-completion-review.json")
raise "Completion report already exists" if File.exist?(output)
LocalEvaluation.atomic_write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
