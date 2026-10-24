# frozen_string_literal: true
require "json"
require "zlib"
require "digest"
require "fileutils"
require "time"
campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
root = File.join(campaign, "amendments/20261023-filesystem-isolation")
path = File.join(root, "replacement-marker-scan.json.gz")
scan = JSON.parse(Zlib::GzipReader.open(path, &:read))
raise "Unexpected scan source/scope" unless scan.fetch("transcripts_scanned") == 24 && scan.fetch("source_commit") == "2c84ee55733daf9fc48a869e5d1f4a068f404f1f"
rows = scan.fetch("observations").map do |row|
  id = row.fetch("id")
  transcript = File.join(scan.fetch("scope"), id, "output.txt")
  raise "Transcript changed" unless Digest::SHA256.file(transcript).hexdigest == row.fetch("transcript_sha256")
  generation = JSON.parse(File.read(File.join(campaign, "observations", "#{id}.json")))
  raise "Isolation evidence missing" unless generation.dig("filesystem_isolation", "policy") == "observation-mount-allowlist-v1" && generation.dig("filesystem_isolation", "preflight", "passed") == true
  { "id" => id, "transcript_sha256" => row.fetch("transcript_sha256"),
    "candidate_events" => row.fetch("candidate_events").map { |e| e.slice("line", "tool", "markers", "output_sha256", "output_bytes") },
    "finding" => row.fetch("candidate_events").empty? ? "no_marker_candidates" : "no_foreign_source_or_evaluator_exposure_found",
    "isolation_implementation_sha256" => generation.dig("filesystem_isolation", "implementation_sha256") }
end
report = { "reviewed_at" => Time.now.utc.iso8601, "source_commit" => scan.fetch("source_commit"),
  "observations" => 24, "candidate_observations" => scan.fetch("candidate_observations"),
  "candidate_events" => rows.sum { |r| r.fetch("candidate_events").size },
  "marker_scan_sha256" => Digest::SHA256.file(path).hexdigest,
  "method" => "Full-file deterministic marker scan of the 24 replacements only; targeted examination of all candidate inputs/excerpts, and full outputs of directory/system searches. Not a full manual transcript read. Every observation also has a passed filesystem-namespace preflight.",
  "findings" => "No successful access to other observations, prior implementations/transcripts, or evaluator material was found. Candidate hits are own-session transcript echoes, own namespace ancestors/current files, and toolchain/environment output. Searches outside the current workspace returned no foreign experiment material.",
  "examples" => [
    { "id" => "roomsim_deepseek-v4.1-flash-oc-high_cuda_r1", "line" => 70, "finding" => "Broad roomsim/grader search found only unrelated system upgrade/Belgrade names, no experiment/evaluator artifacts." },
    { "id" => "roomsim_deepseek-v4.1-flash-oc-high_cuda_r2", "line" => 25, "finding" => "Search of /home, /root and /var for test/verify/reference/roomsim files returned no output." }
  ], "retained_196_reaudited" => false, "other_campaigns_audited" => false, "records" => rows }
output = File.join(root, "replacement-access-review.json")
raise "Review already retained" if File.exist?(output)
File.write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(root, "retain-replacement-access-review.rb"))
puts JSON.pretty_generate(report.except("records", "examples"))
