require "json"
require "digest"
$stdout.sync = true
$stderr.sync = true
campaign = File.read(File.join(__dir__, "campaign.path")).strip
raise "Campaign argument differs" unless ARGV == [campaign]
admission = JSON.parse(File.read(File.join(campaign, "legacy-notification-20261016", "amendment.json")))
admission.fetch("runtime_files").each do |relative, digest|
  raise "Admission parser changed: #{relative}" unless Digest::SHA256.file(File.join(__dir__, relative)).hexdigest == digest
end
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
isolation = JSON.parse(File.read(File.join(campaign, "filesystem-isolation-20261024/amendment.json")))
isolation.fetch("runtime_files").each do |path, digest|
  raise "Filesystem amendment changed: #{path}" unless Digest::SHA256.file(path).hexdigest == digest
end
require File.join(isolation.fetch("working_directory"), "lib/claude_generation_observation")
FABLE_FILESYSTEM_AMENDMENT = isolation

# Substitute only the read-only admission parser. The original controller and
# generation wrapper remain frozen, including the pinned model/CLI and quota fix.
%w[claude_generation_observation experiment_selection].each do |name|
  $LOADED_FEATURES << File.join(manifest.fetch("working_directory"), "lib", "#{name}.rb")
end
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")

# The frozen controller keeps all admission, accounting, cleanup and resume rules.
# Only its per-observation wrapper is redirected to the bound quota-policy variant.
class IsolatedFableGenerationCampaign < GenerationCampaign
  class WeeklyQuotaBoundary < StandardError; end
  
  # Reuse accepted reports byte-for-byte, but require isolation for every new ID.
  def observation(id, baseline: nil)
    unless FABLE_FILESYSTEM_AMENDMENT.fetch("preserved_ids").include?(id)
      path = File.join(@results, id, "claude-filesystem.txt")
      raise "New observation lacks isolation evidence: #{id}" unless File.file?(path)
    end
    super
  end
  
  def execute_observation(id, **options)
    unless File.file?(File.join(@results, id, "timing.txt"))
      ensure_account_idle!
      helper = File.join(@manifest.fetch("working_directory"), "eval_user_support.rb")
      out, error, status = Open3.capture3("su", "-", "llmtest", "--shell=/bin/bash", "-c", Shellwords.join(["ruby", helper, "claude-usage"]))
      raise "Cannot check subscription quota before launch" unless status.success? && out.start_with?("{")
      usage = JSON.parse(out)
      raise "Paid extra usage must remain disabled" unless usage.dig("extra_usage", "is_enabled") == false
      weekly = Array(usage["limits"]).select do |limit|
        next false unless limit["group"] == "weekly" || %w[weekly_all weekly_scoped].include?(limit["kind"])
        name = limit.dig("scope", "model", "display_name") || limit.dig("scope", "model", "id")
        (name.nil? || name.to_s.downcase.include?("fable")) && limit["percent"].to_f >= 95
      end
      shared = usage["seven_day"]
      exhausted = !weekly.empty? || (shared.is_a?(Hash) && (shared["utilization"].to_f >= 95 || !shared["locked_reason"].nil?))
      if exhausted
        json("filesystem-isolation-20261024/quota-pause.json", { "checked_at" => Time.now.utc.iso8601,
          "pending_id" => id, "usage" => usage, "policy" => "Pause between observations at the established 95% weekly boundary; do not reserve the host until the next weekly reset." })
        File.write(File.join(@root, "STOP"), "Fable weekly quota boundary reached; see filesystem-isolation-20261024/quota-pause.json.\n")
        raise WeeklyQuotaBoundary, "Fable weekly allowance consumed to the established reserve"
      end
    end
    super
  end
  
  def run
    super
  rescue WeeklyQuotaBoundary
    snapshot("quota_paused")
  end

  def launch(command)
    original = File.join(@manifest.fetch("runtime_root"), "run.rb")
    raise "Unexpected launch command" unless command.first == "/usr/bin/ruby" && command[1] == original
    super([command.first, File.join(@manifest.fetch("runtime_root"), "run-isolated-20261024.rb"), *command.drop(2)])
  end
end

IsolatedFableGenerationCampaign.new(campaign).run
