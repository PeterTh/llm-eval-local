# frozen_string_literal: true
require "json"
require "digest"
$stdout.sync = $stderr.sync = true
mode = ARGV.fetch(0)
raise "Use preflight or run" unless %w[preflight run].include?(mode) && ARGV.size == 1
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
manifest.fetch("orchestration_files").each { |path, sha| raise "Controller changed" unless Digest::SHA256.file(File.join(__dir__, path)).hexdigest == sha }
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Performance host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")
GenerationCampaign.new(campaign).public_send(mode)
