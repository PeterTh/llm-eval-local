# frozen_string_literal: true

# Read-only comparison of recorded numerical outputs. No compilation/execution.
require "/home/petert/llm_eval/experiment/tools/timing_audit/bin/export_timing_corrections"

final_root = "/home/petert/llm_timing_fixes/20261001-gpt6-qt-final"
original_root = "/home/petert/llm_para_local_evaluation/20261001-gpt6-validation"
corrected_root = "/home/petert/llm_para_local_evaluation/20261001-gpt6-qt-corrected"
artifact_root = "/home/petert/llm-eval-local"
corrections_path = File.join(final_root, "corrections.jsonl")
corrections = TimingAudit.load_jsonl(corrections_path).to_h { |record| [record.fetch("program_id"), record] }
originals = {}
catalog_path = File.join(artifact_root, "release/catalog.json")
catalog = JSON.parse(File.read(catalog_path))
catalog.fetch("campaigns").each do |campaign|
  %w[validation_records corrected_validation_records].each do |key|
    next unless campaign[key]
    Dir[File.join(artifact_root, campaign.fetch(key))].sort.each do |path|
      File.foreach(path) do |line|
        record = JSON.parse(line)
        id = record.fetch("id")
        next unless corrections.key?(id)
        stages = record["stages"] || record.fetch("metadata").fetch("stages")
        raise "Historical comparison baseline is not valid: #{id}" unless TimingCorrectionExport::STAGES.all? { |stage| stages.fetch(stage) == true }
        stdout = record["execution"] ? record.fetch("execution").fetch("stdout") : record.fetch("logs").fetch("validation_out_stdout.log")
        originals[id] = { "stdout" => stdout, "evidence_path" => path,
          "record_sha256" => Digest::SHA256.hexdigest(line), "baseline_kind" => key,
          "note" => "Published validation evidence, including retained prior timing-correction revalidation where available" }
      end
    end
  end
end
LocalEvaluation.load_yaml(File.join(original_root, "validation/all_validation_results.yaml"), permitted_classes: [ValidationResult]).each do |result|
  id = result.id_string
  next unless corrections.key?(id)
  raise "New-batch comparison baseline is not valid: #{id}" unless TimingCorrectionExport::STAGES.all? { |stage| result.public_send(stage) == true }
  path = File.join(original_root, "validation", id, "validation_out_stdout.log")
  originals[id] = { "stdout" => File.read(path), "evidence_path" => path,
    "record_sha256" => LocalEvaluation.sha256_file(path), "baseline_kind" => "initial_gpt6_validation" }
end
results_path = File.join(corrected_root, "validation/all_validation_results.yaml")
results = LocalEvaluation.load_yaml(results_path, permitted_classes: [ValidationResult])
records = results.map do |result|
  id = result.id_string
  raise "Unexpected corrected validation ID: #{id}" unless corrections.key?(id)
  original = originals.fetch(id)
  corrected_path = File.join(corrected_root, "validation", id, "validation_out_stdout.log")
  comparison = TimingCorrectionExport.compare_numerical_outputs(original.fetch("stdout"), File.read(corrected_path))
  { "program_id" => id, "validation_passed" => TimingCorrectionExport::STAGES.all? { |stage| result.public_send(stage) == true },
    "original_evidence" => original.reject { |key, _| key == "stdout" },
    "corrected_stdout_sha256" => LocalEvaluation.sha256_file(corrected_path) }.merge(comparison)
end
raise "Duplicate corrected validation outcomes" unless records.map { |record| record.fetch("program_id") }.uniq.size == records.size
puts JSON.pretty_generate({ "schema_version" => 1, "generated_at" => Time.now.utc.iso8601,
  "policy" => "Compare numerical RESULTS blocks only. Byte identity is supplementary; unchanged numerical validation is authoritative. Retain differing outputs and independently resolve unexpected failures.",
  "correction_registry_sha256" => LocalEvaluation.sha256_file(corrections_path),
  "corrected_validation_results_sha256" => LocalEvaluation.sha256_file(results_path),
  "release_catalog_sha256" => LocalEvaluation.sha256_file(catalog_path),
  "checker_sha256" => LocalEvaluation.sha256_file(__FILE__),
  "expected" => corrections.size, "completed" => records.size,
  "complete" => records.map { |record| record.fetch("program_id") }.sort == corrections.keys.sort,
  "identical" => records.count { |record| record.fetch("numerical_results_identical") },
  "differing_ids" => records.reject { |record| record.fetch("numerical_results_identical") }.map { |record| record.fetch("program_id") },
  "records" => records.sort_by { |record| record.fetch("program_id") } })
