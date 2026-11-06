# frozen_string_literal: true
require "json"
require "open3"
require "fileutils"
require "digest"
require "time"
campaign = "/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra"
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
evidence = manifest.fetch("full_campaign_evidence_root")
raise "Already finalized" if File.exist?(File.join(evidence, "preparation.json"))
raise "Not authorized" unless manifest.fetch("full_campaign_authorized") && manifest["yield_at"].nil?
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
controller_lock = File.open(File.join(campaign, "controller.lock"), "a")
raise "Controller busy" unless controller_lock.flock(File::LOCK_EX | File::LOCK_NB)
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")
driver = GenerationCampaign.new(campaign)
driver.ensure_account_idle!
driver.gate
output, error, status = Open3.capture3("ruby", File.join(manifest.fetch("runtime_root"), "run.rb"),
  "--production", "--continue=20261105-131145")
raise "Dry run failed: #{error}" unless status.success?
raise "Wrong pending count" unless output.include?("Dry run complete. The following 216 runs would have been executed:")
pending = output.lines.last.strip.split(", ")
ids = File.readlines(File.join(campaign, "run-ids.txt"), chomp: true)
raise "Pending IDs differ" unless pending == ids - manifest.fetch("preflight_ids")
skipped = output.lines.grep(/Timing file already exists/).map { |line| line[/configuration: (\S+)/, 1] }
raise "Retained pilot selection differs" unless skipped.sort == manifest.fetch("preflight_ids").sort
def hashes(root)
  paths = Dir[File.join(root, "**", "*"), File.join(root, "**", ".*")].uniq.sort
  raise "Linked pilot data" if paths.any? { |p| File.symlink?(p) }
  paths.select { |p| File.file?(p) }.to_h { |p| [p.delete_prefix(root + "/"), Digest::SHA256.file(p).hexdigest] }
end
retained = manifest.fetch("preflight_ids").to_h { |id| [id, hashes(File.join(manifest.fetch("persistent_results"), id))] }
repair = JSON.parse(File.read(File.join(manifest.fetch("catalog_repair_root"), "repair.json")))
repair.fetch("retained_other_observations").each { |id, expected| raise "Retained pilot changed" unless retained.fetch(id) == expected }
File.write(File.join(evidence, "dry-run.txt"), output)
FileUtils.cp(File.join(evidence, "prepare-full.rb"), File.join(evidence, "prepare-full.initial.rb"))
FileUtils.cp(File.join(__dir__, "prepare-full.rb"), evidence)
FileUtils.cp(__FILE__, evidence)
receipt = { "prepared_at" => Time.now.utc.iso8601, "source_commit" => manifest.fetch("source_commit"),
  "runtime_root" => manifest.fetch("runtime_root"), "full_campaign_authorized" => true,
  "priority_cutoff" => nil, "retained_pilot_files" => retained, "remaining_generation_observations" => pending.size,
  "inferences_launched_during_preparation" => 0,
  "preparation_reporter_note" => "The harness prints 220 total selected IDs before skips and 216 pending IDs at the end; final count and exact pending/skipped lists verified.",
  "authorization" => "User approved remaining 216 Ultra observations and completing the whole experiment before Fable; no need to yield for the weekly reset." }
File.write(File.join(evidence, "preparation.json"), JSON.pretty_generate(receipt) + "\n")
driver.snapshot("preflight_complete")
puts JSON.pretty_generate(receipt.except("retained_pilot_files"))
