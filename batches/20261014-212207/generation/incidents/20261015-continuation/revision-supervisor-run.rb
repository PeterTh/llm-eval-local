require "json"
require "digest"
revision = JSON.parse(File.read(ARGV.fetch(0)))
root = revision.fetch("campaign_root")
raise "Campaign manifest changed" unless Digest::SHA256.file(File.join(root, "campaign.json")).hexdigest == revision.fetch("campaign_manifest_sha256")
raise "Generation launcher changed" unless Digest::SHA256.file(File.join(__dir__, "run.rb")).hexdigest == revision.fetch("generation_launcher_sha256")
revision.fetch("files").each do |relative, digest|
  raise "Supervisor snapshot changed: #{relative}" unless Digest::SHA256.file(File.join(revision.fetch("runtime_copy"), relative)).hexdigest == digest
end
require File.join(revision.fetch("runtime_copy"), "tools/generation_campaign")
$stdout.sync = true
$stderr.sync = true
GenerationCampaign.new(root).run
