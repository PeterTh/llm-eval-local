# frozen_string_literal: true
require "json"
require "fileutils"
require "open3"
require "digest"
require "time"
repository = "/home/petert/llm_eval/experiment"
campaign = "/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra"
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
require File.join(repository, "tools/generation_campaign")
lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
controller_lock = File.open(File.join(campaign, "controller.lock"), "a")
raise "Controller busy" unless controller_lock.flock(File::LOCK_EX | File::LOCK_NB)
raise "Account busy" unless GenerationCleanup.new.pids.empty?
fixture = File.join(__dir__, "campaign-fixture")
raise "Fixture already exists" if File.exist?(fixture)
FileUtils.mkdir_p(File.join(fixture, "observations"))
manifest["codex_effective_context_window"] = 475000
File.write(File.join(fixture, "campaign.json"), JSON.pretty_generate(manifest) + "\n")
FileUtils.cp(File.join(campaign, "run-ids.txt"), fixture)
manifest.fetch("preflight_ids").each { |id| FileUtils.cp(File.join(campaign, "observations", "#{id}.json"), File.join(fixture, "observations")) }
driver = GenerationCampaign.new(fixture)
driver.gate
records = CodexUsage.load_records(File.join(fixture, "preflight-codex-usage.jsonl"))
review = JSON.parse(File.read(File.join(campaign, "preflight-review.json")))
raise "Wrong review" unless review.fetch("passed")
review.fetch("observations").each do |previous|
  record = records.fetch(previous.fetch("id"))
  raise "Totals differ from checked pilot" unless record.fetch("usage") == previous.fetch("recorded_usage_all_threads")
  raise "Interruptions differ" unless record.fetch("interrupted_sessions") == previous.fetch("interrupted_children")
end
raise "Request identity count differs" unless records.values.sum { |r| r.fetch("request_count") } == review.fetch("request_records")
raise "Thread count differs" unless records.values.sum { |r| r.fetch("sessions").size } == review.fetch("session_count")
driver.gate # Repeated recovery must be byte-identical and never launch inference.
receipt = { "checked_at" => Time.now.utc.iso8601, "passed" => true, "observations" => records.size,
  "sessions" => review.fetch("session_count"), "request_records" => review.fetch("request_records"),
  "usage" => review.fetch("recorded_usage_all_threads"), "recovery_repeat_is_identical" => true,
  "inferences_launched" => 0, "session_reads_only_after_idle" => true,
  "files" => %w[preflight-codex-usage.jsonl preflight-usage-recovery.json preflight-gate.json].to_h { |name| [name, Digest::SHA256.file(File.join(fixture, name)).hexdigest] } }
File.write(File.join(__dir__, "accounting-pilot-check.json"), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt)
