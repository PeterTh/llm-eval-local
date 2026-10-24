# frozen_string_literal: true

# Resume only the interrupted generation supplement. The native export and
# metadata-only aggregate amendment have already completed; never repeat them.
require_relative "release/tools/export_opencode_supplement"
require "time"

root = File.join(__dir__, "release")
batch = File.join(root, "batches/20261019-134042")
evaluation = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/evaluation"
native = "/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-validation"
corrected = "/home/petert/llm_para_local_evaluation/20261023-deepseek41-opencode-corrected"
read = ->(base, name) { JSON.parse(File.read(File.join(base, name))) }
hash = ->(path) { Digest::SHA256.file(path).hexdigest }
raise "Export already complete" if File.exist?(File.join(evaluation, "batch-export.json"))
report = read.call(evaluation, "benchmark-completion-review.json")
raise "Benchmark completion not verified" unless report.fetch("verification") == "passed" &&
  report.fetch("completed") == 218 && report.fetch("successful") == 218 && report.fetch("all_records_reconciled")
%w[validation corrected-validation benchmark].each do |stage|
  unit = "llm-deepseek41-oc-#{stage}-20261023.service"
  state, status = Open3.capture2("systemctl", "--user", "show", unit, "--property=ActiveState", "--value")
  raise "Native execution still active: #{unit}" unless status.success? && !%w[active activating deactivating].include?(state.strip)
end
raise "Original validation changed" unless hash.call(File.join(native, "validation/all_validation_results.yaml")) == report.fetch("original_validation_sha256")
raise "Corrected validation changed" unless hash.call(File.join(corrected, "validation/all_validation_results.yaml")) == report.fetch("corrected_validation_sha256")
amendment = read.call(evaluation, "aggregate-export-amendment.json")
raise "Aggregate amendment differs" unless amendment.fetch("scientific_evidence_unchanged") &&
  amendment.fetch("changed_files").keys == ["lib/local_evaluation/aggregate_pipeline.rb"] &&
  hash.call(File.join(native, "pipeline_amendment.yaml")) == amendment.fetch("amendment_sha256") &&
  hash.call(File.join(batch, "benchmark/provenance/pipeline_amendment.yaml")) == amendment.fetch("amendment_sha256")
receipt = read.call(batch, "aggregate/export.json")
raise "Native aggregate differs" unless receipt.fetch("records") == 220 &&
  hash.call(File.join(native, "aggregate_results.csv")) == receipt.fetch("native_aggregate_csv_sha256") &&
  hash.call(File.join(batch, "aggregate/aggregate_results.csv")) == receipt.fetch("native_aggregate_csv_sha256") &&
  hash.call(File.join(native, "aggregate_metadata.yaml")) == receipt.fetch("native_aggregate_metadata_sha256") &&
  hash.call(File.join(batch, "aggregate/aggregate_metadata.yaml")) == receipt.fetch("native_aggregate_metadata_sha256")
guarded = %w[validation timing-audit timing-corrections benchmark aggregate provenance method].flat_map do |directory|
  Dir.glob(File.join(batch, directory, "**/*")).select { |path| File.file?(path) }
end
guarded += [File.join(native, "validation/all_validation_results.yaml"),
  File.join(corrected, "validation/all_validation_results.yaml"),
  File.join(native, "benchmark/benchmark_full_results.yaml"),
  File.join(native, "benchmark/benchmark_run_metadata.yaml"),
  *Dir.glob(File.join(native, "benchmark/*/benchmark_metadata.yaml"))]
before = guarded.sort.uniq.to_h { |path| [path, hash.call(path)] }
OpenCodeSupplement.run(root: root, home: "/home/petert", phase: "complete", batch_id: "20261019-134042")
raise "Existing scientific export changed" unless before.all? { |path, digest| hash.call(path) == digest }
result = {
  "exported_at" => Time.now.utc.iso8601, "batch" => "20261019-134042", "records" => 220,
  "benchmarks" => report.fetch("completed"), "successful" => report.fetch("successful"),
  "corrections" => report.fetch("timing_fixed_records"), "release_workspace" => root,
  "completion_report_sha256" => hash.call(File.join(evaluation, "benchmark-completion-review.json")),
  "driver_sha256" => hash.call(__FILE__),
  "supplement_sha256" => hash.call(File.join(root, "tools/export_opencode_supplement.rb")),
  "resumed_from" => "Completed native export and aggregate import; generation supplement only",
  "resolution" => "Bind original generation method to its original manifest and amended runtime method to the amended manifest; retain both layouts with content deduplication.",
  "existing_scientific_files_unchanged" => before.size,
  "policy" => "Compact native evidence export only. Combined scoring, new-winner analysis, package/site checks and publication are separate gates. No validation or benchmark re-execution."
}
File.write(File.join(evaluation, "batch-export.json"), JSON.pretty_generate(result) + "\n")
%w[resume-batch-export.rb export-completed-batch.rb].each { |name| FileUtils.cp(File.join(__dir__, name), evaluation) }
%w[resume-batch-export.rb export-completed-batch.rb batch-export.json].each do |name|
  FileUtils.cp(File.join(evaluation, name), File.join(batch, "completion", name))
end
puts JSON.pretty_generate(result)
