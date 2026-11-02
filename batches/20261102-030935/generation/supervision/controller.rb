# frozen_string_literal: true
require "json"
action = ARGV.fetch(0)
raise "Use preflight or run" unless %w[preflight run].include?(action)
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")
$stdout.sync = true
$stderr.sync = true
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Another native workload owns the host" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
begin
  GenerationCampaign.new(campaign).public_send(action)
ensure
  host_lock.close
end
