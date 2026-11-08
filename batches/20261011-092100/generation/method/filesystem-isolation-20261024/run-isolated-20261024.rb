require "json"
require "digest"
$stdout.sync = true
$stderr.sync = true
campaign = File.read(File.join(__dir__, "campaign.path")).strip
revision = JSON.parse(File.read(File.join(campaign, "quota-resume-20261016", "amendment.json")))
manifest_path = File.join(campaign, "campaign.json")
raise "Campaign manifest changed" unless Digest::SHA256.file(manifest_path).hexdigest == revision.fetch("campaign_manifest_sha256")
manifest = JSON.parse(File.read(manifest_path))
runtime = manifest.fetch("working_directory")
manifest.fetch("files").each do |relative, digest|
  raise "Launch snapshot changed: #{relative}" unless Digest::SHA256.file(File.join(runtime, relative)).hexdigest == digest
end
manifest.fetch("benchmark_files").each do |relative, digest|
  raise "Sequential input changed: #{relative}" unless Digest::SHA256.file(File.join(__dir__, "benchmarks", relative)).hexdigest == digest
end
revision.fetch("runtime_files").each do |relative, digest|
  raise "Quota amendment changed: #{relative}" unless Digest::SHA256.file(File.join(__dir__, relative)).hexdigest == digest
end
binary = manifest.fetch("claude_binary")
raise "Claude executable changed" unless Digest::SHA256.file(binary).hexdigest == manifest.fetch("claude_binary_sha256")
raise "Production budget required" unless ARGV.include?("--production") && !ARGV.include?("--smoke")
raise "Campaign identity differs" unless ARGV.include?("--continue=#{manifest.fetch('campaign_id')}")
ENV["LLM_EVAL_CLAUDE_BINARY"] = binary
isolation = JSON.parse(File.read(File.join(campaign, "filesystem-isolation-20261024/amendment.json")))
isolation.fetch("runtime_files").each do |path, digest|
  raise "Filesystem amendment changed: #{path}" unless Digest::SHA256.file(path).hexdigest == digest
end
Dir.chdir(isolation.fetch("working_directory"))
load File.join(isolation.fetch("working_directory"), "experiment-isolated.rb")
