# frozen_string_literal: true
require "json"
$stdout.sync = true
$stderr.sync = true
raise "Only pilot is authorized" unless ARGV == ["pilot"]
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
controller_lock = File.open(File.join(campaign, "controller.lock"), "a")
raise "Controller busy" unless controller_lock.flock(File::LOCK_EX | File::LOCK_NB)
driver = GenerationCampaign.new(campaign, yield_at: manifest.fetch("yield_at"))
begin
  manifest.fetch("preflight_ids").each { |id| driver.execute_observation(id, phase: "pilot") }
  driver.ensure_account_idle!
  # Deliberately no legacy parent-only gate/accounting, and no full-run launch.
  driver.snapshot("pilot_captured_pending_multiagent_review")
rescue GenerationCampaign::PriorityPause
  raise
rescue StandardError => e
  driver.snapshot("needs_review", error: "#{e.class}: #{e.message}")
  raise
ensure
  controller_lock.close
  host_lock.close
end
