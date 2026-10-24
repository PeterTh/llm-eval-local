require "json"
require "digest"
require "fileutils"
require "open3"
require "shellwords"
require "time"
require "/tmp/opencode-go-output-limit-controller-20261021.F2iMc4/tools/generation_campaign"

CAMPAIGN = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
RUN_ID = "qtclustering_deepseek-v4.1-flash-oc-high_hybrid_r5"
STATE = "/tmp/opencode-observation-20261023-3026291-raslry/private"
INCIDENT = File.join(CAMPAIGN, "incidents/20261023-agent-self-termination")

def native_projection(tables)
  raise "Expected exactly one native session" unless tables.fetch("session").size == 1
  row = tables.fetch("session").first
  info = row.slice("id", "title", "directory", "version", "cost").merge(
    "parentID" => row.fetch("parent_id"),
    "time" => { "created" => row.fetch("time_created"), "updated" => row.fetch("time_updated") },
    "tokens" => { "input" => row.fetch("tokens_input"), "output" => row.fetch("tokens_output"),
      "reasoning" => row.fetch("tokens_reasoning"),
      "cache" => { "read" => row.fetch("tokens_cache_read"), "write" => row.fetch("tokens_cache_write") } })
  parts = tables.fetch("part").sort_by { |part| [part.fetch("time_created"), part.fetch("id")] }.map do |part|
    JSON.parse(part.fetch("data")).merge("id" => part.fetch("id"), "messageID" => part.fetch("message_id"), "sessionID" => part.fetch("session_id"))
  end
  messages = tables.fetch("message").sort_by { |message| [message.fetch("time_created"), message.fetch("id")] }.map do |message|
    { "info" => JSON.parse(message.fetch("data")).merge("id" => message.fetch("id"), "sessionID" => message.fetch("session_id")),
      "parts" => parts.select { |part| part.fetch("messageID") == message.fetch("id") } }
  end
  last_tool = messages.last.fetch("parts").reverse.find { |part| part["type"] == "tool" }
  projected = OpenCodeHarness.session_projection(info, messages)
  projected.fetch("messages").last.fetch("parts").map! { |part| part["id"] == last_tool.fetch("id") ? last_tool : part }
  [projected, last_tool]
end

if ARGV == ["--read-native"]
  database = File.join(STATE, "data/opencode/opencode.db")
  tables = %w[session message part].to_h do |table|
    output, error, status = Open3.capture3("sqlite3", "-readonly", "-json", database, "SELECT * FROM #{table};")
    raise "Read-only native export failed: #{error}" unless status.success?
    [table, JSON.parse(output)]
  end
  files = %w[prepared.json opencode-config.txt opencode-events.txt].to_h { |name| [name, File.binread(File.join(STATE, name))] }
  payload = JSON.generate({ "tables" => tables, "files" => files })
  credential = JSON.parse(File.read(File.join(STATE, "data/opencode/auth.json"))).fetch("opencode-go").fetch("key")
  raise "Credential found in evidence" if payload.include?(credential)
  puts payload
  exit
end

old = File.join(CAMPAIGN, "incidents/20261020-agent-self-termination/native-session-rows.json")
previous, = native_projection(JSON.parse(File.read(old)))
previous_saved = "/home/petert/llm_para_experiments/20261019-134042/qtclustering_deepseek-v4.1-flash-oc-high_mpi_r2/opencode-session.txt"
raise "Projection differs from previously accepted recovery" unless previous == JSON.parse(File.read(previous_saved))
if ARGV == ["--self-test"]
  puts "Native projection exactly matches the previously accepted recovery (JSON equality)."
  exit
end
raise "Use --self-test or --retain" unless ARGV == ["--retain"]
raise "Incident already retained" if File.exist?(INCIDENT)
manifest = JSON.parse(File.read(File.join(CAMPAIGN, "campaign.json")))
result = File.join(manifest.fetch("persistent_results"), RUN_ID)
raise "Observation already admitted" if File.exist?(File.join(CAMPAIGN, "observations", "#{RUN_ID}.json"))
unit_state, status = Open3.capture2("systemctl", "--user", "show", manifest.fetch("generation_unit"), "-p", "ActiveState", "--value")
raise "Queue is not stopped" unless status.success? && unit_state.strip == "failed"
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is active" unless status.exitstatus == 1 && pids.empty?
original = Dir[File.join(result, "**", "*")].select { |path| File.file?(path) }.to_h do |path|
  raise "Unexpected symlink" if File.symlink?(path)
  [path.delete_prefix(result + "/"), Digest::SHA256.file(path).hexdigest]
end
unchanged = Dir[File.join(CAMPAIGN, "observations", "*.json")].to_h { |path| [File.basename(path), Digest::SHA256.file(path).hexdigest] }
raise "Unexpected accepted count" unless unchanged.size == 215
command = Shellwords.join(["ruby", __FILE__, "--read-native"])
output, error, status = Open3.capture3("su", "-", "llmtest", "--shell=/bin/bash", "-c", command)
raise "Native export failed: #{error}" unless status.success?
native = JSON.parse(output)
session, last_tool = native_projection(native.fetch("tables"))
raise "Different final native tool" unless last_tool.fetch("id") == "prt_1663f231e001UZS76zFzTLW8BX"
raise "Different termination command" unless last_tool.dig("state", "input", "command").start_with?("pkill -f qtclustering 2>/dev/null; pkill -f 'mpirun.*qtclustering' 2>/dev/null;")
raise "Wrong native session" unless session.dig("info", "title") == RUN_ID && session.dig("info", "parentID").nil?
raise "Unexpected native termination state" unless last_tool.dig("state", "status") == "running" && !session.fetch("messages").last.dig("info", "time", "completed")
process = JSON.parse(File.read(File.join(result, "process-status.txt")))
raise "Different process outcome" unless process == { "exit_status" => 143, "term_signal" => nil, "success" => false, "timeout_seconds" => 14400 }
files = native.fetch("files").merge("native-session-rows.json" => JSON.pretty_generate(native.fetch("tables")) + "\n")
FileUtils.mkdir_p(INCIDENT, mode: 0700)
files.each { |name, content| File.write(File.join(INCIDENT, name), content, mode: "wx", perm: 0600) }
%w[cleanup quota].each { |kind| FileUtils.cp(File.join(CAMPAIGN, kind, "#{RUN_ID}.json"), File.join(INCIDENT, "#{kind}.json")) }
record = { "observed_at" => Time.now.utc.iso8601, "id" => RUN_ID, "classification" => "model_caused_termination",
  "cause" => "The model's broad pkill -f qtclustering command terminated its own harness process chain; the parent moved the workspace before child evidence publication completed.",
  "decision" => "retain_original_without_restart", "approval_basis" => "Apply the user's standing decision for the identical earlier model-caused self-termination; preserve the original attempt and use normal validation.",
  "previous_incident" => "incidents/20261020-agent-self-termination", "termination_tool_part" => last_tool,
  "process_status" => process, "original_files_sha256" => original, "previous_observation_sha256" => unchanged,
  "retained_artifacts_sha256" => files.keys.to_h { |name| [name, Digest::SHA256.file(File.join(INCIDENT, name)).hexdigest] },
  "generation_repeated" => false, "source_changed" => false, "credentials_retained" => false, "native_database_retained" => false,
  "usage_caveat" => "Completed-request native counters are a lower bound; the interrupted final request has no completion record." }
File.write(File.join(INCIDENT, "incident.json"), JSON.pretty_generate(record) + "\n", mode: "wx", perm: 0600)
FileUtils.cp(__FILE__, File.join(INCIDENT, "retain.rb"))
%w[opencode-config.txt opencode-events.txt].each do |name|
  File.write(File.join(result, name), native.fetch("files").fetch(name), mode: "wx")
end
File.write(File.join(result, "opencode-session.txt"), JSON.pretty_generate(session) + "\n", mode: "wx")
termination = { "schema_version" => 1, "run_id" => RUN_ID, "session_id" => session.dig("info", "id"),
  "reason" => "model_caused_termination", "approved_by" => "user", "decision" => "retain_original_without_restart",
  "approval_basis" => record.fetch("approval_basis"), "recorded_at" => Time.now.utc.iso8601,
  "usage_complete" => false, "native_process_receipt_available" => false, "metadata_source" => "read_only_native_database_export",
  "termination_tool_part" => last_tool, "incident_sha256" => Digest::SHA256.file(File.join(INCIDENT, "incident.json")).hexdigest,
  "native_export_sha256" => Digest::SHA256.file(File.join(INCIDENT, "native-session-rows.json")).hexdigest,
  "metadata_sha256" => OpenCodeGenerationTermination::METADATA.to_h { |name| [name, Digest::SHA256.file(File.join(result, name)).hexdigest] } }
File.write(File.join(result, OpenCodeGenerationTermination::FILENAME), JSON.pretty_generate(termination) + "\n", mode: "wx")
baseline = JSON.parse(File.read(File.join(CAMPAIGN, "preflight-gate.json"))).fetch("preflights").first
report = GenerationCampaign.new(CAMPAIGN).observation(RUN_ID, baseline: baseline)
raise "Wrong admission outcome" unless report.fetch("outcome") == "generation_model_terminated" && report.fetch("usage_complete") == false
original.each { |name, sha| raise "Original changed: #{name}" unless Digest::SHA256.file(File.join(result, name)).hexdigest == sha }
unchanged.each { |name, sha| raise "Earlier observation changed: #{name}" unless Digest::SHA256.file(File.join(CAMPAIGN, "observations", name)).hexdigest == sha }
summary = report.slice("id", "outcome", "usage_complete", "raw_total_seconds", "total_seconds", "total_tokens", "retry_count", "retry_backoff_seconds", "output_token_policy")
summary.merge!("prior_observations_unchanged" => unchanged.size, "original_files_unchanged" => original.size, "rerun_performed" => false)
File.write(File.join(INCIDENT, "recovery.json"), JSON.pretty_generate(summary) + "\n", mode: "wx")
puts JSON.pretty_generate(summary)

