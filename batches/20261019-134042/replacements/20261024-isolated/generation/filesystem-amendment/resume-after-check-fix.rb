# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"
campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
amendment = File.join(campaign, "amendments/20261023-filesystem-isolation")
receipt_path = File.join(amendment, "amendment.json")
receipt = JSON.parse(File.read(receipt_path))
runtime = receipt.fetch("runtime_root")
unit = receipt.fetch("generation_unit")
source = "/tmp/deepseek-isolated-replacements-driver-20261023.rb"
raise "Already amended" if File.exist?(File.join(amendment, "controller-check-fix.json"))
state, status = Open3.capture2("systemctl", "--user", "show", unit, "--property=ActiveState", "--value")
raise "Controller is still active" unless status.success? && !%w[active activating deactivating].include?(state.strip)
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Account busy" unless status.exitstatus == 1 && pids.empty?
old = File.read(File.join(runtime, "run-replacements.rb"))
new_code = File.read(source)
before = '    result = driver.execute_observation(id, baseline: baseline, phase: "isolated_replacements")'
after = "    driver.execute_observation(id, baseline: baseline, phase: \"isolated_replacements\")\n    result = driver.observation(id, baseline: baseline)"
raise "Unexpected controller change" unless old.scan(before).size == 1 && old.sub(before, after) == new_code
raise "Recorded driver differs" unless Digest::SHA256.hexdigest(old) == receipt.fetch("driver_sha256")
require File.join(receipt.fetch("runtime_root"), "experiment/tools/generation_campaign")
driver = GenerationCampaign.new(campaign)
baseline = JSON.parse(File.read(File.join(campaign, "preflight-gate.json"))).fetch("preflights").first
first_id = receipt.fetch("affected_observations").first
prior = driver.observation(first_id, baseline: baseline)
raise "First replacement invalid" unless prior.fetch("outcome") == "completed" && prior.dig("filesystem_isolation", "policy") == receipt.fetch("filesystem_policy")
raise "Resume would not reuse first completed observation" unless driver.execute_observation(first_id, baseline: baseline) == prior
receipt.fetch("affected_observations").drop(1).each do |id|
  raise "Another replacement already exists" if File.exist?(File.join(campaign, "observations", "#{id}.json"))
end
FileUtils.cp(File.join(runtime, "run-replacements.rb"), File.join(amendment, "run-replacements-before-check-fix.rb"))
FileUtils.cp(receipt_path, File.join(amendment, "amendment-before-check-fix.json"))
FileUtils.cp(File.join(amendment, "progress.json"), File.join(amendment, "controller-check-stop.json"))
[File.join(runtime, "run-replacements.rb"), File.join(amendment, "run-replacements.rb")].each { |path| FileUtils.cp(source, path) }
old_sha = receipt.fetch("driver_sha256")
receipt["driver_sha256"] = Digest::SHA256.file(source).hexdigest
File.write(receipt_path, JSON.pretty_generate(receipt) + "\n")
fix = { "fixed_at" => Time.now.utc.iso8601,
  "cause" => "execute_observation returns a campaign progress snapshot after a fresh run; the replacement wrapper mistakenly treated that return as the per-observation report.",
  "correction" => "Read and verify the independently retained observation after execute_observation returns.",
  "old_driver_sha256" => old_sha, "new_driver_sha256" => receipt.fetch("driver_sha256"),
  "completed_observation_preserved" => first_id, "repeat_inferences" => 0,
  "remaining_observations" => 23, "scientific_or_harness_method_changed" => false }
File.write(File.join(amendment, "controller-check-fix.json"), JSON.pretty_generate(fix) + "\n")
FileUtils.cp(__FILE__, File.join(amendment, "resume-after-check-fix.rb"))
raise "Reset failed" unless system("systemctl", "--user", "reset-failed", unit)
raise "Resume failed" unless system("systemctl", "--user", "start", unit)
puts JSON.pretty_generate(fix)
