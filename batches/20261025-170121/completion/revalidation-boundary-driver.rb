# frozen_string_literal: true

$stdout.sync = true
require_relative "verify-revalidation-boundary"

# Preserve the original native method and its provenance. The added operator
# check is separately pinned and required before this stage can authorize any
# benchmark; no source or historical native record is rewritten.
load File.join(__dir__, "revalidation-driver.rb")
B = BeamRevalidationBoundary
manifest, ids, reference = B.inputs
run_lock = LocalEvaluation::RunLock.new(B::ROOT)
host_lock = LocalEvaluation::HostPerformanceLock.new
raise "Supplemental completion already exists" if File.exist?(B::REPORT)
runner, resources = LocalEvaluation::ProcessRunner.new, LocalEvaluation::Resources.new
ids.each do |id|
  directory = File.join(B::ROOT, "external-validation", B::CASE.fetch("id"), id)
  result_path = File.join(directory, "result.json")
  if File.file?(result_path)
    B.verify_record!(id, manifest, reference)
    next
  end
  raise "Partial supplemental attempt requires inspection: #{id}" if File.exist?(directory)
  info = manifest.runs.fetch(id)
  executable = LocalEvaluation::BuildSupport.find_executable(File.join(B::ROOT, "validation", id), info.fetch("benchmark"))
  prefix = File.join(directory, "validation_out")
  execution, output = LocalEvaluation::ExternalValidationCases.run(executable: executable, definition: B::CASE,
    par_type: info.fetch("par_type"), prefix: prefix, runner: runner, resources: resources,
    timeout: LocalEvaluation::ValidationPipeline::VALIDATION_TIMEOUT)
  comparison = LocalEvaluation::ExternalValidationCases.assess(reference, output, execution)
  result = { "id" => id, "source_commit" => manifest.data.dig("experiment_repository", "commit"),
    "source_path" => "#{info.fetch('batch')}/#{id}", "manifest_sha256" => LocalEvaluation.sha256_file(manifest.path),
    "args" => B::CASE.fetch("args"), "executable_sha256" => LocalEvaluation.sha256_file(executable),
    "reference_sha256" => Digest::SHA256.hexdigest(reference), "checked_at" => Time.now.utc.iso8601,
    "passed" => comparison.first, "comparison" => comparison, "execution" => execution.to_h.transform_keys(&:to_s),
    "logs" => LocalEvaluation::ExternalValidationCases.log_digests(prefix) }
  LocalEvaluation.atomic_write(result_path, JSON.pretty_generate(result) + "\n")
  B.verify_record!(id, manifest, reference)
  puts "Supplemental external comparison passed: #{id}"
end
paths = [manifest.path, __FILE__, File.join(__dir__, "revalidation-driver.rb"), File.join(__dir__, "verify-revalidation-boundary.rb"),
  File.join(__dir__, "experiment-supplemental/lib/local_evaluation/external_validation_cases.rb"), BeamExternalValidation::REGISTRY]
report = { "schema_version" => 1, "checked_at" => Time.now.utc.iso8601, "passed" => true, "ids" => ids,
  "source_commit" => manifest.data.dig("experiment_repository", "commit"), "case" => B::CASE,
  "inputs_sha256" => paths.to_h { |path| [path, LocalEvaluation.sha256_file(path)] },
  "result_sha256" => ids.to_h { |id| [id, LocalEvaluation.sha256_file(File.join(B::ROOT, "external-validation", B::CASE.fetch("id"), id, "result.json"))] },
  "policy" => "Original native validation plus required additional external comparison, unchanged sequential/generated programs and comparator. No retries." }
LocalEvaluation.atomic_write(B::REPORT, JSON.pretty_generate(report) + "\n")
B.verify!
host_lock.close
run_lock.close
puts JSON.pretty_generate(report)
