# frozen_string_literal: true

require_relative "experiment/lib/local_evaluation"
require_relative "experiment-supplemental/lib/local_evaluation/external_validation_cases"
require_relative "verified-external-validation"

module BeamRevalidationBoundary
  ROOT = "/home/petert/llm_para_local_evaluation/20261030-beam10-opencode-corrected"
  CAMPAIGN = BeamExternalValidation::CAMPAIGN
  REPORT = File.join(CAMPAIGN, "external-revalidation-completion.json")
  CASE = LocalEvaluation::ExternalValidationCases::UNSTRUCTURED_BOUNDARY
  module_function

  def inputs
    external = BeamExternalValidation.verify!
    manifest = LocalEvaluation::Manifest.new(ROOT)
    manifest.verify_input_revisions!
    expected = manifest.runs.select { |_id, info| info.fetch("benchmark") == "unstructured" && %w[mpi hybrid].include?(info.fetch("par_type")) }.keys.sort
    raise "Excluded source entered revalidation" unless (manifest.runs.keys & external.fetch(:excluded)).empty?
    reference = external.fetch(:registry).data.fetch("reference").fetch("stdout")
    [manifest, expected, reference]
  end

  def verify_record!(id, manifest, reference)
    directory = File.join(ROOT, "external-validation", CASE.fetch("id"), id)
    result = JSON.parse(File.read(File.join(directory, "result.json")))
    info = manifest.runs.fetch(id)
    executable = LocalEvaluation::BuildSupport.find_executable(File.join(ROOT, "validation", id), info.fetch("benchmark"))
    unless result.fetch("id") == id && result.fetch("source_commit") == manifest.data.dig("experiment_repository", "commit") &&
        result.fetch("source_path") == "#{info.fetch('batch')}/#{id}" && result.fetch("args") == CASE.fetch("args") &&
        result.fetch("manifest_sha256") == LocalEvaluation.sha256_file(manifest.path) &&
        result.fetch("executable_sha256") == LocalEvaluation.sha256_file(executable) &&
        result.fetch("reference_sha256") == Digest::SHA256.hexdigest(reference)
      raise "Corrected supplemental input differs: #{id}"
    end
    prefix = File.join(directory, "validation_out")
    raise "Corrected supplemental logs changed: #{id}" unless result.fetch("logs") == LocalEvaluation::ExternalValidationCases.log_digests(prefix)
    output = File.read(prefix + "_stdout.log")
    execution = result.fetch("execution")
    unless execution.fetch("success") && execution.fetch("exit_code") == 0 && !execution.fetch("timed_out") &&
        output.include?("Validation: PASSED") && !output.include?("Validation: FAILED") && !output.include?("Validation fail") &&
        result.fetch("passed") && result.fetch("comparison") == validate(reference, output, "unstructured") && result.fetch("comparison").first
      raise "Corrected supplemental external validation failed: #{id}; preserve without retry and investigate"
    end
    result
  end

  def verify!
    manifest, ids, reference = inputs
    report = JSON.parse(File.read(REPORT))
    unless report.fetch("passed") && report.fetch("ids") == ids && report.fetch("source_commit") == manifest.data.dig("experiment_repository", "commit")
      raise "Incomplete corrected-source supplemental validation"
    end
    report.fetch("inputs_sha256").each { |path, sha| raise "Supplemental revalidation input changed: #{path}" unless LocalEvaluation.sha256_file(path) == sha }
    ids.each do |id|
      verify_record!(id, manifest, reference)
      path = File.join(ROOT, "external-validation", CASE.fetch("id"), id, "result.json")
      raise "Corrected supplemental record changed" unless LocalEvaluation.sha256_file(path) == report.fetch("result_sha256").fetch(id)
    end
    report
  end
end

puts JSON.pretty_generate(BeamRevalidationBoundary.verify!) if $PROGRAM_NAME == __FILE__
