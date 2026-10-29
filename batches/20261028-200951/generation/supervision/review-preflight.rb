# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

campaign = File.read(File.join(__dir__, "campaign.path")).strip
target = File.join(campaign, "preflight-review.json")
raise "Already reviewed" if File.exist?(target)
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
require File.join(manifest.fetch("working_directory"), "lib/codex_generation_observation")
id = manifest.fetch("preflight_ids").fetch(0)
gate = JSON.parse(File.read(File.join(campaign, "preflight-gate.json")))
raise "Gate incomplete" unless gate.fetch("accepted") && gate.fetch("preflights").size == 1
directory = File.join(manifest.fetch("persistent_results"), id)
report = CodexGenerationObservation.read(directory, model: "gpt-6.1-terra", effort: "medium", version: "0.160.1")
raise "Pilot changed after gate" unless report == gate.fetch("preflights").fetch(0)
raise "Incomplete native invocation" unless report.fetch("outcome") == "completed"
usage = File.readlines(File.join(campaign, "preflight-codex-usage.jsonl")).map { |line| CodexUsage.validate_record!(JSON.parse(line)) }
raise "Wrong exact-usage scope" unless usage.size == 1 && usage.first.fetch("run_id") == id
CodexUsage.verify_transcript!(usage.first, id: id, batch: manifest.fetch("campaign_id"), path: File.join(directory, "output.txt"))
archived = report.fetch("archived_sessions").find { |row| row.fetch("path") == usage.first.fetch("session_path") }
raise "Native session not bound" unless archived && archived.fetch("sha256") == usage.first.fetch("session_sha256")
companion = report.fetch("filesystem_isolation").fetch("harness_companions").fetch("codex-code-mode-host")
raise "Companion differs" unless companion.fetch("sha256") == manifest.fetch("codex_companions").fetch("codex-code-mode-host").fetch("sha256")
cleanup = JSON.parse(File.read(File.join(campaign, "cleanup", "#{id}.json")))
raise "Account cleanup not verified" unless cleanup.fetch("verified_empty")
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Account currently busy" unless status.exitstatus == 1 && pids.empty?
text = File.read(File.join(directory, "output.txt"))
successful_tools = text.scan(/^ succeeded in \d+ms:/).size
raise "Tool capability not demonstrated" unless successful_tools >= 1 && text.include?("patch: completed")
raise "Tool-host infrastructure error" if text.include?("Code Mode is unavailable") || text.include?("failed to spawn code-mode host")
attempt = JSON.parse(File.read(File.join(campaign, "infrastructure-attempts/001-missing-code-mode-host/review.json")))
raise "Setup attempt not excluded" unless attempt.fetch("excluded_from_experimental_observations") && attempt.fetch("program_source_unchanged")
record = {
  "reviewed_at" => Time.now.utc.iso8601, "passed" => true, "id" => id,
  "criterion" => "Requested harness/model/effort/budget, functioning native tools, filesystem isolation, exact accounting and cleanup; no selection on program correctness or performance.",
  "source_commit" => manifest.fetch("source_commit"), "native_generation_seconds" => report.fetch("raw_total_seconds"),
  "successful_shell_tool_calls" => successful_tools, "editing_capability_demonstrated" => true,
  "exact_usage" => usage.first.fetch("usage"), "native_session_sha256" => usage.first.fetch("session_sha256"),
  "original_setup_inference_attempts" => 1, "retained_production_pilot_attempts" => 1,
  "retained_pilot_reexecuted" => false, "reused_in_full_campaign" => true,
  "prior_setup_attempt" => "infrastructure-attempts/001-missing-code-mode-host/review.json",
  "scientific_validation_pending" => true, "account_cleanup_verified" => true,
  "evidence_sha256" => %w[preflight-gate.json preflight-codex-usage.jsonl filesystem-preflight.json tool-host-amendment.json].to_h { |name| [name, Digest::SHA256.file(File.join(campaign, name)).hexdigest] },
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
File.write(target, JSON.pretty_generate(record) + "\n")
FileUtils.cp(__FILE__, File.join(campaign, File.basename(__FILE__)))
puts JSON.pretty_generate(record)
