# frozen_string_literal: true
require "json"
require "digest"
$stdout.sync = true
$stderr.sync = true
raise "No arguments" unless ARGV.empty?
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
raise "Full campaign not authorized" unless manifest.fetch("full_campaign_authorized") == true
raise "Unexpected priority cutoff" if manifest["yield_at"]
manifest.fetch("orchestration_files").each do |name, sha|
  raise "Controller changed" unless Digest::SHA256.file(File.join(__dir__, name)).hexdigest == sha
end
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")
GenerationCampaign.new(campaign).run
