require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

root = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
incident = File.join(root, "incidents/20261023-agent-self-termination")
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
queue_root = manifest.fetch("queue_root")
queue = JSON.parse(File.read(File.join(queue_root, "queue.json")))
unit = manifest.fetch("generation_unit")
raise "Generation unit mismatch" unless queue.fetch("generation_unit") == unit
raise "Resume already recorded" if File.exist?(File.join(incident, "resume.json"))
state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
raise "Unit is not stopped" unless status.success? && state.strip == "failed"
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Account is active" unless status.exitstatus == 1 && pids.empty?
raise "DeepSeek is operator-held" if File.exist?(File.join(root, "STOP")) || File.exist?(File.join(queue_root, "STOP"))
raise "MiniMax hold missing" unless File.file?(File.join(queue.fetch("campaigns").last, "STOP"))
raise "Fable hold missing" unless File.file?(File.join(manifest.fetch("paused_campaign").fetch("path"), "STOP"))
manifest.fetch("files").each do |relative, sha|
  raise "Frozen generation method changed: #{relative}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), relative)).hexdigest == sha
end
admitted = Dir[File.join(root, "observations/*.json")].map { |path| File.basename(path, ".json") }
raise "Accepted observation count differs" unless admitted.size == 216
next_id = (File.readlines(File.join(root, "run-ids.txt"), chomp: true) - admitted).first
raise "Next observation differs" unless next_id == "roomsim_deepseek-v4.1-flash-oc-high_hybrid_r5"
output, status = Open3.capture2e("systemctl", "--user", "restart", unit)
raise "Resume failed: #{output}" unless status.success?
record = { "resumed_at" => Time.now.utc.iso8601, "unit" => unit, "retained_observations" => admitted.size,
  "next_id" => next_id, "generation_repeated" => false, "generation_settings_changed" => false,
  "generation_method_changed" => false, "minimax_held" => true, "fable_priority_preserved" => true,
  "recovery_sha256" => Digest::SHA256.file(File.join(incident, "recovery.json")).hexdigest }
File.write(File.join(incident, "resume.json"), JSON.pretty_generate(record) + "\n", mode: "wx")
FileUtils.cp(__FILE__, File.join(incident, "resume.rb"))
puts JSON.pretty_generate(record)

