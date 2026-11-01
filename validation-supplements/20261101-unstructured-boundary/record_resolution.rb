# frozen_string_literal: true

require_relative "boundary_check"
B = UnstructuredBoundaryCheck
verification_path = File.join(B::EVIDENCE, "verification.json")
verification = B.read_json(verification_path)
findings_path = File.join(B::EVIDENCE, "static-findings.json")
findings = B.read_json(findings_path)
raise "Verification failed" unless verification.fetch("verified")
raise "Findings refer to another verification" unless findings.fetch("verification_sha256") == B.sha(verification_path)
raise "Not every failure has a disposition" unless findings.fetch("records").map { |row| row.fetch("id") }.sort == verification.fetch("failures").map { |row| row.fetch("id") }.sort
raise "A disposition changes an algorithm" unless findings.fetch("records").all? { |row| row.fetch("disposition") == "fail_validation; preserve original source and all measurements; no algorithm repair" }
approval_path = File.join(B::EVIDENCE, "approval-and-launch.json")
approval = B.read_json(approval_path)
hold = approval.fetch("original_hold")
raise "Original hold changed" unless B.sha(hold) == approval.fetch("original_hold_sha256")
campaign = File.dirname(hold)
native_path = File.join(campaign, "validation-completion-review.json")
native = B.read_json(native_path)
raise "Native validation pass count differs" unless native.fetch("passed") == verification.fetch("beam_native_passes")
eligible = verification.fetch("beam_eligible_ids")
excluded = verification.fetch("beam_excluded_ids")
raise "Known incorrect Beam program remains eligible" unless excluded.include?(B::KNOWN_BAD) && !eligible.include?(B::KNOWN_BAD)
corrections = verification.fetch("beam_eligible_timing_correction_ids")
raise "An ineligible program remains selected for correction" unless (corrections - eligible).empty?
resolution = {
  "schema_version" => 1, "recorded_at" => Time.now.utc.iso8601,
  "status" => "scientific_disposition_resolved; downstream_eligibility_integration_pending",
  "original_hold_sha256" => B.sha(hold), "user_approval_sha256" => B.sha(approval_path),
  "supplemental_evidence_root" => B::EVIDENCE,
  "supplemental_verification_sha256" => B.sha(verification_path),
  "static_findings_sha256" => B.sha(findings_path),
  "native_validation_report_sha256" => B.sha(native_path),
  "native_validation_passes" => native.fetch("passed"),
  "beam_excluded_ids" => excluded, "beam_eligible_ids" => eligible,
  "beam_eligible_count" => eligible.size, "beam_eligible_timing_correction_ids" => corrections,
  "beam_eligible_timing_corrections" => corrections.size,
  "historical_excluded_ids" => verification.fetch("failures").select { |row| row.fetch("origin") == "published_successful_measurement" }.map { |row| row.fetch("id") },
  "published_winner_impact" => verification.fetch("published_winner_impact"),
  "policy" => "Preserve all originals and raw validation/benchmark evidence. Apply supplemental failures as additive validation exclusions. Keep timing review verdicts intact, but omit ineligible programs from timing correction and benchmarking. No algorithm repairs, no performance reruns. Passing programs need no new model reviews.",
  "remaining_integration" => [
    "Teach correction inventory and benchmark eligibility to consume this verified exclusion overlay without modifying the original validation/audit evidence.",
    "Retain compact supplemental evidence in the release, apply historical exclusions and recompute derived scores/rankings without rerunning measurements.",
    "Use the boundary-crossing case for subsequent Unstructured MPI/hybrid validation."
  ]
}
B.write_json(File.join(campaign, "scientific-followup-resolution.json"), resolution)
B.write_json(File.join(B::EVIDENCE, "beam-disposition.json"), resolution)
FileUtils.cp(__FILE__, B::EVIDENCE)
puts JSON.pretty_generate(resolution.reject { |key, _value| %w[beam_eligible_ids beam_eligible_timing_correction_ids].include?(key) })
