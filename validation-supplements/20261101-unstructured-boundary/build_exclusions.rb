# frozen_string_literal: true
require_relative "boundary_check"
require "/home/petert/llm_eval/experiment/tools/timing_audit/lib/external_validation_exclusions"
B = UnstructuredBoundaryCheck
verification = B.read_json(File.join(B::EVIDENCE, "verification.json"))
findings = B.read_json(File.join(B::EVIDENCE, "static-findings.json"))
raise "Unverified dispositions" unless verification.fetch("verified") && findings.fetch("verification_sha256") == B.sha(File.join(B::EVIDENCE, "verification.json"))
failed = verification.fetch("failures")
raise "Findings do not cover failures" unless failed.map { |row| row.fetch("id") }.sort == findings.fetch("records").map { |row| row.fetch("id") }.sort
reference = File.read(File.join(B::EVIDENCE, "results/sequential_reference/validation_out_stdout.log"))
records = failed.sort_by { |row| row.fetch("id") }.map do |failure|
  id = failure.fetch("id")
  result_path = File.join(B::EVIDENCE, "results", id, "result.json")
  raise "Verified result changed" unless B.sha(result_path) == failure.fetch("result_sha256")
  { "id" => id, "source_commit" => failure.fetch("source_commit"), "source_path" => failure.fetch("source_path"),
    "stages" => ExternalValidationExclusions::STAGES, "result" => B.read_json(result_path),
    "result_sha256" => failure.fetch("result_sha256"),
    "stdout" => File.read(File.join(File.dirname(result_path), "validation_out_stdout.log")) }
end
data = { "schema_version" => 1, "created_at" => Time.now.utc.iso8601, "record_count" => records.size,
  "failed_stage" => "output_comparison",
  "case" => { "id" => ExternalValidationExclusions::CASE_ID, "benchmark" => "unstructured", "args" => B::ARGS, "mpi_ranks" => 4 },
  "authorization" => { "source" => "user", "statement" => "Treat these as failing the appropriate validation step (external validation). Include it in all future validation. (Of course there should be no change to the input programs to maintain the same conditions). Add a research note in the repo. Then continue as standard." },
  "validation_helper_sha256" => B.sha("/home/petert/llm_eval/experiment/validation_helper.rb"),
  "reference" => { "stdout" => reference, "stdout_sha256" => Digest::SHA256.hexdigest(reference), "source_commit" => B::REFERENCE_COMMIT },
  "evidence_sha256" => %w[manifest.json full-manifest.json completion.json verification.json static-findings.json].to_h { |name| [name, B.sha(File.join(B::EVIDENCE, name))] },
  "records" => records }
path = File.join(B::EVIDENCE, "external-validation-exclusions.json")
B.write_json(path, data)
verified = ExternalValidationExclusions.new(path)
FileUtils.cp(__FILE__, B::EVIDENCE)
puts JSON.pretty_generate({ "path" => path, "sha256" => verified.digest, "records" => verified.records.size,
  "beam_excluded_ids" => verified.ids_for(source_commit: "74652eee82e2473660a7e75f3ad5d77fd0e3759c", ids: verification.fetch("beam_excluded_ids")) })
