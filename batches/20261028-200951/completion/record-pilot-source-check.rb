# frozen_string_literal: true
require "json"
require "digest"
require "time"
require "fileutils"

evaluation = "/home/petert/llm_para_campaigns/20261028-200951-terra61-codex-medium/evaluation"
audit = "/home/petert/llm_timing_audit/20261029-terra61-codex"
source = File.join(__dir__, "generated/20261028-200951")
checks = [
  [audit, "roomsim_gpt-6.1-terra-medium_mpi_r4", "roomsim/roomsim.cpp", "36-40, 911-949, 987-993", "Root-only printf macro and three local phase durations; canonical sum lacks timing aggregation."],
  [audit, "nbody_gpt-6.1-terra-medium_hybrid_r3", "nbody/nbody.cpp", "205-223", "Complete GPU work is synchronized; MPI_MAX combines local durations and the reduced value is printed."],
  [audit, "cholesky_gpt-6.1-terra-medium_hybrid_r3", "cholesky/cholesky.cpp", "68-104", "Start/end barriers and final device synchronization exist, but the canonical interval is root-local, as the established contract explicitly distinguishes from MPI_MAX."],
  [audit + "-qtclustering", "qtclustering_gpt-6.1-terra-medium_cuda_r3", "qtclustering/qtclustering.cpp", "107-202, 313-326", "On-demand distances and clustering are inside the timed call, with blocking GPU transfers before return; no excluded distance preprocessing."],
  [audit + "-qtclustering", "qtclustering_gpt-6.1-terra-medium_mpi_r4", "qtclustering/qtclustering.cpp", "270-292", "The full clustering call is locally timed, but nonroots finalize without a duration reduction and root prints its own time."]
]
report = {
  "checked_at" => Time.now.utc.iso8601, "passed" => true,
  "scope" => "Representative source-grounded usability spot-check, not blanket scientific adjudication; the established independent review and uncertainty-only Sol stages remain required.",
  "source_commit" => "c94e9a7be1efbb0235af8cd31fdb9f5c7b994a36",
  "checks" => checks.map { |root, id, file, lines, finding| {
    "program_id" => id, "review_root" => root, "path" => file, "lines" => lines, "finding" => finding,
    "source_sha256" => Digest::SHA256.file(File.join(source, id, file)).hexdigest,
    "response_sha256" => Digest::SHA256.file(File.join(root, "results", "#{id}.json")).hexdigest
  } },
  "pilot_retry" => "One primary response was rejected for an invalid evidence line range, retained, and retried by the existing bounded schema verifier. No generated program was rerun.",
  "review_cli_diagnostic" => "The code-mode-host-disabled diagnostic is expected for intentionally tool-disabled static workers; event verification confirms zero tool executions. Do not enable execution tools to remove this diagnostic."
}
path = File.join(evaluation, "pilot-source-quality-review.json")
raise "Spot-check already recorded" if File.exist?(path)
File.write(path, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, evaluation)
puts JSON.pretty_generate(report.slice("checked_at", "passed", "scope", "pilot_retry"))
