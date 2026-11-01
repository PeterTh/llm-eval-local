# frozen_string_literal: true

require_relative "artifact_common"

# Retain compact, independently re-checkable evidence, never executable caches.
module ExternalValidationExport
  extend LocalEvalArtifact
  module_function

  def run(evidence:, root:, method_root:)
    require File.join(method_root, "tools/timing_audit/lib/external_validation_exclusions")
    registry = ExternalValidationExclusions.new(File.join(evidence, "external-validation-exclusions.json"))
    report = JSON.parse(File.read(File.join(evidence, "verification.json")))
    raise "Unverified supplemental campaign" unless report.fetch("verified")
    base = File.join(root, "validation-supplements/20261101-unstructured-boundary")
    raise "Supplemental export already exists" if File.exist?(base)
    rows = report.fetch("checks").sort_by { |row| row.fetch("id") }.map do |check|
      id = check.fetch("id")
      directory = File.join(evidence, "results", id)
      result_path = File.join(directory, "result.json")
      raise "Supplemental result changed: #{id}" unless sha256(result_path) == check.fetch("result_sha256")
      result = JSON.parse(File.read(result_path))
      logs = check.fetch("log_sha256").to_h do |name, digest|
        file = File.join(directory, "validation_out_#{name}.log")
        raise "Supplemental log changed: #{id}/#{name}" unless sha256(file) == digest
        [name, File.read(file)]
      end
      comparison = validate(registry.data.fetch("reference").fetch("stdout"), logs.fetch("stdout"), "unstructured")
      unless result.fetch("comparison") == comparison && result.fetch("passed") == comparison.first &&
          result.dig("execution", "success") && !result.dig("execution", "timed_out") && result.fetch("internal_validation")
        raise "Supplemental verdict does not reproduce: #{id}"
      end
      { "id" => id, "result" => result, "result_sha256" => check.fetch("result_sha256"),
        "logs" => logs, "log_sha256" => check.fetch("log_sha256") }
    end
    raise "Supplemental coverage differs" unless rows.size == report.fetch("total") &&
      rows.reject { |row| row.dig("result", "passed") }.map { |row| row.fetch("id") } == registry.records.keys
    FileUtils.mkdir_p(base)
    write_jsonl(File.join(base, "records.jsonl"), rows)
    names = %w[approval-and-launch.json beam-disposition.json completion.json execution-inventory.jsonl
      external-validation-exclusions.json full-manifest.json host.json inventory.jsonl manifest.json pilot.json
      reference.json regression-tests.log static-findings.json verification.json boundary_check.rb full_check.rb
      test_boundary_check.rb verify_completion.rb record_findings.rb record_resolution.rb build_exclusions.rb]
    names.each { |name| FileUtils.cp(File.join(evidence, name), File.join(base, name)) }
    reference_dir = File.join(evidence, "results/sequential_reference")
    reference = JSON.parse(File.read(File.join(reference_dir, "result.json")))
    reference_logs = %w[command stdout stderr exitcode wall_time].to_h do |name|
      [name, File.read(File.join(reference_dir, "validation_out_#{name}.log"))]
    end
    raise "Reference differs from exclusion evidence" unless reference_logs.fetch("stdout") == registry.data.fetch("reference").fetch("stdout")
    File.write(File.join(base, "reference-output.json"), JSON.pretty_generate({ "result" => reference, "logs" => reference_logs }) + "\n")
    Dir[File.join(evidence, "builds/*/*")].sort.each do |file|
      name = File.basename(file)
      next unless name == "source_staging.yaml" || name == "build-binding.json" || name.match?(/\A(?:cmake|build)_(?:command|stdout|stderr|exitcode|wall_time)\.log\z/)
      destination = File.join(base, "builds", File.basename(File.dirname(file)), name)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(file, destination)
    end
    %w[tools/timing_audit/lib/external_validation_exclusions.rb validation_helper.rb].each do |relative|
      destination = File.join(root, "method/external-validation", relative)
      raise "Method snapshot exists" if File.exist?(destination)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(File.join(method_root, relative), destination)
    end
    exported = regular_files(base)
    receipt = { "schema_version" => 1, "records" => rows.size, "failed" => registry.records.size,
      "registry_sha256" => registry.digest, "files_sha256" => exported.to_h { |file| [relative_path(base, file), sha256(file)] },
      "retained_bytes" => exported.sum { |file| File.size(file) },
      "policy" => "Exact source pins, native result and bounded execution/build logs; no binaries, build workspaces or repeated generated sources. Original result JSON reconstructs from each JSONL result object." }
    File.write(File.join(base, "export.json"), JSON.pretty_generate(receipt) + "\n")
    puts JSON.pretty_generate(receipt.slice("records", "failed", "retained_bytes", "registry_sha256"))
  end
end

if $PROGRAM_NAME == __FILE__
  raise "Usage: export_external_validation.rb EVIDENCE ROOT METHOD_ROOT" unless ARGV.size == 3
  ExternalValidationExport.run(evidence: ARGV[0], root: ARGV[1], method_root: ARGV[2])
end
