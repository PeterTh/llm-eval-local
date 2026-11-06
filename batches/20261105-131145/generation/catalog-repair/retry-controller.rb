# frozen_string_literal: true
require "json"
require "digest"
$stdout.sync = true
$stderr.sync = true
raise "No arguments" unless ARGV.empty?
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
controller_lock = File.open(File.join(campaign, "controller.lock"), "a")
raise "Controller busy" unless controller_lock.flock(File::LOCK_EX | File::LOCK_NB)
driver = GenerationCampaign.new(campaign, yield_at: manifest.fetch("yield_at"))
begin
  target = manifest.fetch("catalog_retry_id")
  raise "Wrong retry scope" unless target == "matmul_gpt-6.1-terra-ultra_cuda_r1" && !manifest.fetch("full_campaign_authorized")
  report = driver.execute_observation(target, phase: "pilot_catalog_retry")
  raise "Missing pinned catalog" unless report.fetch("model_catalog").fetch("sha256") == manifest.fetch("codex_model_catalog").fetch("sha256")
  repair = JSON.parse(File.read(File.join(manifest.fetch("catalog_repair_root"), "repair.json")))
  repair.fetch("retained_other_observations").each do |id, files|
    files.each do |relative, sha|
      raise "Retained observation changed: #{id}/#{relative}" unless Digest::SHA256.file(File.join(manifest.fetch("persistent_results"), id, relative)).hexdigest == sha
    end
  end
  driver.ensure_account_idle!
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
