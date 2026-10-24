require "json"
require "fileutils"
require "digest"
require "open3"
require "time"

campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
id = "cholesky_deepseek-v4.1-flash-oc-high_cuda_r2"
source = File.join(manifest.fetch("persistent_results"), id)
target = File.join(campaign, "incidents/20261021-initial-503")
raise "Failure already retained; do not retry again automatically" if File.exist?(target)
raise "Admitted observation must never be retried" if File.file?(File.join(campaign, "observations", "#{id}.json"))
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Account busy" unless status.exitstatus == 1 && pids.empty?
unit = manifest.fetch("generation_unit")
state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
raise "Queue not failed" unless status.success? && state.strip == "failed"
raise "Nonempty transcript requires investigation" unless File.zero?(File.join(source, "output.txt"))
session = JSON.parse(File.read(File.join(source, "opencode-session.txt")))
assistants = session.fetch("messages").select { |message| message.dig("info", "role") == "assistant" }
raise "Unexpected native session" unless assistants.size == 1 && assistants.first.fetch("parts").empty?
header = assistants.first.fetch("info")
raise "Not the observed infrastructure error" unless header.dig("error", "name") == "APIError" && header.dig("error", "data", "statusCode") == 503 && header.dig("error", "data", "isRetryable")
tokens = header.fetch("tokens")
raise "Completed model usage exists" unless tokens.values_at("input", "output", "reasoning").all?(&:zero?) && tokens.fetch("cache").values.all?(&:zero?)
evidence = JSON.parse(File.read(File.join(source, "opencode-config.txt")))
raise "Policy differs" unless evidence.fetch("output_token_policy") == manifest.fetch("opencode_output_token_policy")
hashes = Dir[File.join(source, "**", "*")].select { |p| File.file?(p) }.to_h { |p| [p.delete_prefix(source + "/"), Digest::SHA256.file(p).hexdigest] }
FileUtils.mkdir_p(target, mode: 0700)
FileUtils.mv(source, File.join(target, id))
%w[cleanup quota].each do |kind|
  FileUtils.cp(File.join(campaign, kind, "#{id}.json"), File.join(target, "#{kind}.json"))
end
receipt = { "recorded_at" => Time.now.utc.iso8601, "run_id" => id,
  "classification" => "provider_unavailable_before_any_model_output", "http_status" => 503,
  "model_tool_calls" => 0, "native_completed_request_tokens" => 0,
  "decision" => "Preserve failed infrastructure start and retry the same already-authorized replacement once, with identical settings",
  "settings_changed" => false, "output_token_policy" => evidence.fetch("output_token_policy"), "original_files_sha256" => hashes }
File.write(File.join(target, "incident.json"), JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, File.join(target, "retain-and-retry.rb"))
raise "Queue STOP present" if File.exist?(File.join(manifest.fetch("queue_root"), "STOP")) || File.exist?(File.join(campaign, "STOP"))
raise "Restart failed" unless system("systemctl", "--user", "restart", unit)
puts JSON.pretty_generate(receipt.reject { |key, _| key == "original_files_sha256" })
