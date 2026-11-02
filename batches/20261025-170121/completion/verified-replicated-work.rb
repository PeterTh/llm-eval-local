# frozen_string_literal: true
require_relative "verified-external-validation"
module BeamReplicatedWork
  module_function
  def verify!
    external = BeamExternalValidation.verify!
    path = File.join(BeamExternalValidation::CAMPAIGN, "replicated-work-correction-selection-20261101.json")
    resolution = JSON.parse(File.read(path))
    raise "Replica reconciliation failed" unless resolution.fetch("passed") && resolution.fetch("source_commit") == BeamExternalValidation::ORIGINAL_COMMIT
    resolution.fetch("input_sha256").each { |file, sha| raise "Replica reconciliation evidence changed: #{file}" unless Digest::SHA256.file(file).hexdigest == sha }
    ids = resolution.fetch("correction_ids")
    raise "Correction selection malformed" unless ids == ids.sort.uniq && ids.size == resolution.fetch("corrections") && !ids.empty?
    raise "Validation selection changed" unless resolution.fetch("external_validation_excluded_ids") == external.fetch(:excluded) && resolution.fetch("benchmark_eligible_ids") == external.fetch(:eligible_ids)
    raise "Replica/excluded program selected for correction" unless (ids & (resolution.fetch("accepted_unchanged_replica_ids") + external.fetch(:excluded))).empty?
    resolution
  end
end
