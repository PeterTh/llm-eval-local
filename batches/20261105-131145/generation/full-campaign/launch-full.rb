# frozen_string_literal: true
require "json"
require "open3"
require "time"
require "digest"
raise "No arguments" unless ARGV.empty?
campaign = "/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra"
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
evidence = manifest.fetch("full_campaign_evidence_root")
raise "Already launched" if File.exist?(File.join(evidence, "launch.json"))
raise "Stopped" if File.exist?(File.join(campaign, "STOP"))
raise "Campaign not authorized" unless manifest.fetch("full_campaign_authorized") && manifest.fetch("phase") == "production_generation" && manifest["yield_at"].nil?
raise "Preparation not accepted" unless JSON.parse(File.read(File.join(evidence, "preparation.json"))).fetch("remaining_generation_observations") == 216
raise "Pilot gate not accepted" unless JSON.parse(File.read(File.join(campaign, "preflight-gate.json"))).fetch("accepted")
def checked(*args)
  output, error, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{error}\n#{output}" unless status.success?
  output
end
units = checked("systemctl", "--user", "list-units", "--type=service", "--state=active,activating", "--no-legend", "--no-pager", "llm-*")
active = units.lines.map { |line| line.strip.split.first }.reject { |name| name.include?("-monitor-") }
raise "Another evaluation workload active: #{active}" unless active.empty?
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "llmtest busy" unless status.exitstatus == 1 && pids.empty?
manifest.fetch("orchestration_files").each do |name, sha|
  raise "Orchestration changed" unless Digest::SHA256.file(File.join(manifest.fetch("runtime_root"), name)).hexdigest == sha
end
output = checked("systemd-run", "--user", "--unit=#{manifest.fetch('generation_unit')}", "--description=Terra 6.1 Ultra full generation with native delegation",
  "--property=Type=exec", "--property=WorkingDirectory=#{manifest.fetch('working_directory')}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{evidence}/generation.log", "--property=StandardError=append:#{evidence}/generation.log",
  "/usr/bin/ruby", File.join(manifest.fetch("runtime_root"), "full-controller.rb"))
receipt = { "launched_at" => Time.now.utc.iso8601, "unit" => manifest.fetch("generation_unit"),
  "source_commit" => manifest.fetch("source_commit"), "systemd_output" => output,
  "completed_pilots_reused" => 4, "remaining_observations" => 216, "priority_cutoff" => nil }
File.write(File.join(evidence, "launch.json"), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt)
