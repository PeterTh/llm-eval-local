# frozen_string_literal: true
require_relative "verified-replicated-work"
module BeamFinalReplicaSelection
  module_function
  def verify!
    prior = BeamReplicatedWork.verify!
    path = File.join(BeamExternalValidation::CAMPAIGN, "final-replica-correction-selection-20261101.json")
    resolution = JSON.parse(File.read(path))
    raise "Final replica selection not complete" unless resolution.fetch("passed") && resolution.fetch("all_corrections_compiled_and_accepted")
    resolution.fetch("input_sha256").each { |file, sha| raise "Final replica evidence changed: #{file}" unless Digest::SHA256.file(file).hexdigest == sha }
    ids = resolution.fetch("correction_ids")
    raise "Unexpected final correction subset" unless ids == prior.fetch("correction_ids") - ["cahn-hilliard_beam-1.0-oc-medium_hybrid_r4"] && ids.size == resolution.fetch("corrections")
    raise "Native eligibility/source changed" unless resolution.fetch("benchmark_eligible_ids") == prior.fetch("benchmark_eligible_ids") && resolution.fetch("source_commit") == prior.fetch("source_commit")
    raise "Accepted replica selected for correction" unless (ids & resolution.fetch("accepted_unchanged_replica_ids")).empty?
    resolution
  end
end
