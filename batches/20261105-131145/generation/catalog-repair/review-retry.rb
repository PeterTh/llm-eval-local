# frozen_string_literal: true
require "json"
require "open3"
require "shellwords"
require "digest"
require "fileutils"
require "time"

campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
repair = manifest.fetch("catalog_repair_root")
raise "Review already retained" if File.exist?(File.join(repair, "completed-review.json"))
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
controller_lock = File.open(File.join(campaign, "controller.lock"), "a")
raise "Controller busy" unless controller_lock.flock(File::LOCK_EX | File::LOCK_NB)
progress = JSON.parse(File.read(File.join(campaign, "progress.json")))
known_reporter_error = progress.fetch("status") == "needs_review" && progress["error"] == 'KeyError: key not found: "model_catalog"'
raise "Pilot not stopped" unless (progress.fetch("status") == "pilot_captured_pending_multiagent_review" || known_reporter_error) && progress.fetch("completed") == 4 && progress["active_id"].nil?
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Never inspect live sessions" unless status.exitstatus == 1 && pids.empty?
require File.join(manifest.fetch("working_directory"), "lib/codex_generation_observation")
reports = manifest.fetch("preflight_ids").map do |id|
  fresh = CodexGenerationObservation.read(File.join(manifest.fetch("persistent_results"), id),
    model: "gpt-6.1-terra", effort: "ultra", version: manifest.fetch("codex_version"))
  retained = JSON.parse(File.read(File.join(campaign, "observations", "#{id}.json")))
  raise "Observation evidence differs" unless fresh == retained
  raise "Unexpected outcome" unless fresh.fetch("outcome") == "completed"
  fresh
end
requests = reports.map { |r| r.slice("id", "archived_sessions") }
read = lambda do |helper, input|
  stdout, stderr, status = Open3.capture3("su", "-", "llmtest", "--shell=/bin/bash", "-c",
    Shellwords.join(["ruby", File.join(__dir__, helper), "--reader"]), stdin_data: JSON.generate(input))
  raise "Archive review failed: #{stderr}" unless status.success?
  stdout.lines.map { |line| JSON.parse(line) }
end
records = read.call("session-reader.rb", requests)
identities = read.call("closed-children-reader.rb", records.flat_map { |r| r.fetch("sessions") })
total = Hash.new(0)
usage = records.map do |observation|
  report = reports.find { |r| r.fetch("id") == observation.fetch("id") }
  combined = Hash.new(0)
  sessions = observation.fetch("sessions").map do |session|
    meta = session.fetch("meta")
    raise "Model/effort differs" unless session.fetch("models").all? { |m| m["model"] == "gpt-6.1-terra" && m["effort"] == "ultra" }
    raise "Unexpected context metadata" unless session.fetch("token_counts").all? { |e| e.fetch("info").fetch("model_context_window") == 475000 }
    final = session.fetch("token_counts").last.fetch("info").fetch("total_token_usage")
    sum = Hash.new(0)
    session.fetch("usage_records").each { |entry| entry.fetch("fields").fetch("usage").each { |k,v| sum[k] += v } }
    raise "Request/cumulative usage differs" unless sum == final && session.fetch("usage_records").last.fetch("fields").fetch("thread_token_usage") == final
    final.each { |k,v| combined[k] += v; total[k] += v }
    if meta.fetch("id") == report.fetch("session_id")
      raise "Root legacy counter differs" unless final.fetch("total_tokens") - final.fetch("cached_input_tokens") == report.fetch("legacy_reported_tokens")
    end
    { "session_id" => meta.fetch("id"), "parent_session_id" => meta["forked_from_id"], "archive" => session.fetch("archive"),
      "model" => "gpt-6.1-terra", "effort" => "ultra", "usage" => final,
      "final_task_event" => session.fetch("task_events").last, "request_count" => session.fetch("usage_records").size }
  end
  raise "Root scope differs" unless sessions.count { |s| s["parent_session_id"].nil? && s["session_id"] == report.fetch("session_id") } == 1
  sessions.each do |s|
    raise "Unknown parent" if s["parent_session_id"] && !sessions.any? { |p| p["session_id"] == s["parent_session_id"] }
  end
  aborted = sessions.select { |s| s.fetch("final_task_event").fetch("type") == "turn_aborted" }.map { |s| s.fetch("session_id") }
  { "id" => observation.fetch("id"), "generation_seconds" => report.fetch("raw_total_seconds"), "sessions" => sessions,
    "recorded_usage_all_threads" => combined, "interrupted_child_request_usage_uncertain" => !aborted.empty?,
    "interrupted_children" => aborted, "recorded_request_counters_reconciled" => true }
end
repair_receipt = JSON.parse(File.read(File.join(repair, "repair.json")))
fingerprints = lambda do |root|
  Dir[File.join(root, "**", "*"), File.join(root, "**", ".*")].uniq.sort.select { |p| File.file?(p) }.to_h { |p| [p.delete_prefix(root + "/"), Digest::SHA256.file(p).hexdigest] }
end
repair_receipt.fetch("retained_other_observations").each do |id, expected|
  raise "Unrelated observation changed" unless fingerprints.call(File.join(manifest.fetch("persistent_results"), id)) == expected
end
raise "Superseded evidence changed" unless fingerprints.call(repair_receipt.fetch("original_attempt")) == repair_receipt.fetch("original_files")
reports.each do |r|
  raise "Cleanup not verified" unless JSON.parse(File.read(File.join(campaign, "cleanup", "#{r.fetch('id')}.json"))).fetch("verified_empty")
end
replacement = reports.find { |r| r.fetch("id") == manifest.fetch("catalog_retry_id") }
raise "Missing bound catalog" unless replacement.fetch("model_catalog").fetch("sha256") == manifest.fetch("codex_model_catalog").fetch("sha256")
replacement_head = File.read(File.join(manifest.fetch("persistent_results"), manifest.fetch("catalog_retry_id"), "output.txt"), 16384)
raise "Retry still has metadata errors" if replacement_head.match?(/failed to refresh available models|Defaulting to fallback metadata/)
proof = { "reviewed_at" => Time.now.utc.iso8601, "passed" => true, "accepted_for_full_campaign" => true,
  "full_campaign_authorized" => false, "full_campaign_started" => false,
  "observations" => usage, "repeated_ids" => [manifest.fetch("catalog_retry_id")],
  "other_three_observations_byte_identical" => true, "superseded_attempt_preserved" => true,
  "retry_has_no_metadata_errors" => true, "all_sessions_use_native_terra_ultra_metadata" => true,
  "all_cleanup_checks_passed" => true, "unique_request_identity_check" => true,
  "catalog_sha256" => manifest.fetch("codex_model_catalog").fetch("sha256"),
  "recorded_usage_all_threads" => total, "generation_seconds" => usage.sum { |r| r.fetch("generation_seconds") },
  "session_count" => usage.sum { |r| r.fetch("sessions").size },
  "request_records" => identities.sum { |r| r.fetch("request_count") },
  "accounting_policy" => "Sum recorded unique requests across parent and all child threads. Preserve native cancellation and flag interrupted-request uncertainty; do not report the parent-only count as complete usage.",
  "validation_or_benchmarking_started" => false,
  "remaining_generation_observations" => manifest.fetch("expected_runs") - reports.size }
if known_reporter_error
  proof["post_run_reporter_warning"] = { "error" => progress.fetch("error"),
    "cause" => "The retry controller treated execute_observation's progress-snapshot return value as an observation report.",
    "resolution" => "Read and independently verify the already-retained observation report; no inference repeated." }
end
File.write(File.join(repair, "session-inspection.json"), JSON.pretty_generate(records) + "\n")
File.write(File.join(repair, "request-identity-and-shutdown.json"), JSON.pretty_generate(identities) + "\n")
File.write(File.join(repair, "recorded-tree-usage.jsonl"), usage.map { |r| JSON.generate(r) + "\n" }.join)
File.write(File.join(repair, "completed-review.json"), JSON.pretty_generate(proof) + "\n")
File.write(File.join(campaign, "preflight-review.json.tmp"), JSON.pretty_generate(proof) + "\n")
File.rename(File.join(campaign, "preflight-review.json.tmp"), File.join(campaign, "preflight-review.json"))
%w[review-retry.rb session-reader.rb closed-children-reader.rb].each { |name| FileUtils.cp(File.join(__dir__, name), repair) }
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")
GenerationCampaign.new(campaign).snapshot("preflight_complete")
puts JSON.pretty_generate(proof.except("observations", "accounting_policy"))
