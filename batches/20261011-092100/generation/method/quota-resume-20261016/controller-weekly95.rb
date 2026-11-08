require "json"
require "digest"
$stdout.sync = true
$stderr.sync = true
campaign = File.read(File.join(__dir__, "campaign.path")).strip
raise "Campaign argument differs" unless ARGV == [campaign]
revision = JSON.parse(File.read(File.join(campaign, "quota-resume-20261016", "amendment.json")))
manifest_path = File.join(campaign, "campaign.json")
raise "Campaign manifest changed" unless Digest::SHA256.file(manifest_path).hexdigest == revision.fetch("campaign_manifest_sha256")
manifest = JSON.parse(File.read(manifest_path))
manifest.fetch("files").each do |relative, digest|
  raise "Launch snapshot changed: #{relative}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), relative)).hexdigest == digest
end
revision.fetch("runtime_files").each do |relative, digest|
  raise "Quota amendment changed: #{relative}" unless Digest::SHA256.file(File.join(__dir__, relative)).hexdigest == digest
end
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")

# The frozen controller keeps all admission, accounting, cleanup and resume rules.
# Only its per-observation wrapper is redirected to the bound quota-policy variant.
class WeeklyQuotaGenerationCampaign < GenerationCampaign
  def launch(command)
    original = File.join(@manifest.fetch("runtime_root"), "run.rb")
    raise "Unexpected launch command" unless command.first == "/usr/bin/ruby" && command[1] == original
    super([command.first, File.join(@manifest.fetch("runtime_root"), "run-weekly95.rb"), *command.drop(2)])
  end
end

WeeklyQuotaGenerationCampaign.new(campaign).run
