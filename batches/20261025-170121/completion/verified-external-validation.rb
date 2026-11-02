# frozen_string_literal: true

require "json"
require "digest"
require_relative "experiment-supplemental/tools/timing_audit/lib/external_validation_exclusions"

module BeamExternalValidation
  CAMPAIGN = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
  EVIDENCE = "/home/petert/llm_para_campaigns/20261101-unstructured-boundary-validation"
  REGISTRY = File.join(EVIDENCE, "external-validation-exclusions.json")
  REGISTRY_SHA256 = "5c234270bcbc46005a714c1221a9af85a8f7d09c0d2fbfbbbe7e3398cce1d6e0"
  ORIGINAL_COMMIT = "74652eee82e2473660a7e75f3ad5d77fd0e3759c"
  EXCLUDED_ID = "unstructured_beam-1.0-oc-medium_mpi_r2"
  module_function

  def verify!
    registry = ExternalValidationExclusions.new(REGISTRY)
    raise "External-validation disposition changed" unless registry.digest == REGISTRY_SHA256
    resolution_path = File.join(CAMPAIGN, "scientific-followup-resolution.json")
    resolution = JSON.parse(File.read(resolution_path))
    paths = {
      File.join(CAMPAIGN, "scientific-followup-hold.json") => resolution.fetch("original_hold_sha256"),
      File.join(CAMPAIGN, "validation-completion-review.json") => resolution.fetch("native_validation_report_sha256"),
      File.join(EVIDENCE, "verification.json") => resolution.fetch("supplemental_verification_sha256"),
      File.join(EVIDENCE, "static-findings.json") => resolution.fetch("static_findings_sha256"),
      REGISTRY => REGISTRY_SHA256
    }
    paths.each { |path, sha| raise "Supplemental evidence changed: #{path}" unless Digest::SHA256.file(path).hexdigest == sha }
    verification = JSON.parse(File.read(File.join(EVIDENCE, "verification.json")))
    raise "Incomplete supplemental check" unless verification.values_at("verified", "total", "passed", "failed") == [true, 287, 279, 8]
    beam_ids = registry.records.keys.select { |id| id.include?("_beam-1.0-oc-medium_") }
    excluded = registry.ids_for(source_commit: ORIGINAL_COMMIT, ids: beam_ids)
    unless excluded == [EXCLUDED_ID] && resolution.fetch("beam_excluded_ids") == excluded &&
        resolution.fetch("beam_eligible_ids").size == 179 && resolution.fetch("native_validation_passes") == 180
      raise "Unexpected Beam external-validation selection"
    end
    paths[resolution_path] = Digest::SHA256.file(resolution_path).hexdigest
    { registry: registry, excluded: excluded, eligible_ids: resolution.fetch("beam_eligible_ids"), paths: paths }
  end
end
