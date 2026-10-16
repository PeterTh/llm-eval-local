require "json"
require "digest"
require "fileutils"
require "tmpdir"
require "time"
require "shellwords"
require "open3"
require "/home/petert/llm_eval/experiment/tools/generation_campaign"
require "/home/petert/llm_eval/experiment/lib/local_evaluation"

root = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium"
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
incident_root = File.join(root, "incidents/20261015-oom")
incident_path = File.join(incident_root, "incident.json")
incident = JSON.parse(File.read(incident_path))
id = "qtclustering_claude-sonnet-5.5-cc-medium_omp_r2"
raise "Wrong incident" unless incident.fetch("run_id") == id && incident.fetch("campaign_id") == manifest.fetch("campaign_id")
receipt_path = File.join(incident_root, "recovery.json")
raise "Recovery already recorded" if File.exist?(receipt_path)
raise "STOP guard absent" unless File.file?(File.join(root, "STOP"))
raise "Account is not idle" unless GenerationCleanup.new.pids.empty?
state, status = Open3.capture2("systemctl", "--user", "show", manifest.fetch("generation_unit"), "-p", "ActiveState", "--value")
raise "Controller state changed" unless status.success? && state.strip == "failed"

manifest.fetch("files").each do |relative, digest|
  raise "Frozen harness changed: #{relative}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), relative)).hexdigest == digest
end
manifest.fetch("benchmark_files").each do |relative, digest|
  raise "Frozen input changed: #{relative}" unless Digest::SHA256.file(File.join(manifest.fetch("runtime_root"), "benchmarks", relative)).hexdigest == digest
end
raise "CLI changed" unless Digest::SHA256.file(manifest.fetch("claude_binary")).hexdigest == manifest.fetch("claude_binary_sha256")

results = manifest.fetch("persistent_results")
prior = incident.fetch("completed_observations_verified")
raise "Canonical scope changed" unless Dir.children(results).sort == prior.keys.sort && prior.size == 50
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflight")
prior.each do |completed_id, evidence|
  path = File.join(root, "observations", "#{completed_id}.json")
  raise "Previous report changed: #{completed_id}" unless Digest::SHA256.file(path).hexdigest == evidence.fetch("report_sha256")
  report = ClaudeGenerationObservation.read(File.join(results, completed_id), model: manifest.fetch("invoked_model"),
    version: manifest.fetch("claude_version"), timeout_seconds: manifest.fetch("per_run_timeout_seconds"), baseline: baseline, batch: manifest.fetch("campaign_id"))
  raise "Previous observation changed: #{completed_id}" unless report == JSON.parse(File.read(path))
end

workspace = incident.fetch("preserved_workspace")
original = File.join(incident_root, "original-workspace")
actual_paths = Dir.glob(File.join(workspace, "**/*"), File::FNM_DOTMATCH).reject { |p| File.directory?(p) }.map { |p| p.delete_prefix(workspace + "/") }.sort
raise "Workspace scope changed" unless actual_paths == incident.fetch("workspace_files").keys.sort
incident.fetch("workspace_files").each do |relative, data|
  [workspace, original].each do |base|
    path = File.join(base, relative)
    raise "Original artifact changed: #{relative}" unless !File.symlink?(path) && Digest::SHA256.file(path).hexdigest == data.fetch("sha256")
  end
end

# Recover the exact prompt from the recorded invocation, cross-checking the
# unchanged same-benchmark/backend prompt used in the first repetition.
log_lines = File.readlines(File.join(root, "generation.log"))
indices = log_lines.each_index.select { |index| log_lines[index].strip == "Command for #{id}:" }
raise "Ambiguous invocation" unless indices.size == 1
command = Shellwords.split(log_lines.fetch(indices.first + 1)).last
arguments = Shellwords.split(command)
effort_index = arguments.index("--effort")
raise "Invocation identity differs" unless arguments[effort_index + 1] == "medium" && arguments[arguments.index("--model") + 1] == manifest.fetch("invoked_model")
prompt = arguments.fetch(effort_index + 2)
prior_prompt = File.join(results, "qtclustering_claude-sonnet-5.5-cc-medium_omp_r1", "instruction.txt")
raise "Prompt differs from original same-backend observation" unless prompt == File.binread(prior_prompt)
result = incident.fetch("agent_terminal_result")
raise "Native duration differs" unless result.fetch("duration_ms") == 865229 && result.fetch("duration_api_ms") == 61451

staging = Dir.mktmpdir("sonnet55-recovered-", "/tmp")
directory = File.join(staging, id)
FileUtils.cp_r(original, directory, preserve: true)
File.write(File.join(directory, "instruction.txt"), prompt)
File.write(File.join(directory, "timing.txt"), "Start time: unavailable (generation wrapper terminated)\nEnd time: unavailable (generation wrapper terminated)\nDuration: 865.229 seconds\nGeneration time source: claude_result_duration_ms (recovered)\nWrapper wall time: unavailable\nRecovery evidence: generation-recovery.txt\n")
File.write(File.join(directory, "process-status.txt"), JSON.pretty_generate({ "exit_status" => nil, "term_signal" => nil, "success" => nil,
  "timeout_seconds" => manifest.fetch("per_run_timeout_seconds"), "status_source" => "unavailable_controller_terminated" }) + "\n")
File.write(File.join(directory, "usage.txt"), "Windows before run: unavailable\nScoped limits before run: unavailable\nResult record: #{JSON.generate(result)}\nRecovery evidence: generation-recovery.txt\n")
record = { "schema_version" => 1, "reason" => "controller_oom", "approved_by" => "user", "decision" => "retain_completed_native_result",
  "approval_recorded_at" => Time.now.utc.iso8601, "run_id" => id, "campaign_id" => manifest.fetch("campaign_id"),
  "session_id" => result.fetch("session_id"), "model" => manifest.fetch("invoked_model"), "version" => manifest.fetch("claude_version"),
  "incident_sha256" => Digest::SHA256.file(incident_path).hexdigest,
  "duration_ms" => result.fetch("duration_ms"), "generation_time_source" => ClaudeGenerationRecovery::TIME_SOURCE,
  "generation_time_recovered" => true, "wrapper_exit_status_available" => false,
  "wrapper_wall_time_seconds" => nil, "wrapper_start_time" => nil, "wrapper_end_time" => nil,
  "note" => "The generation supervisor stopped after a child OOM, but the original Claude invocation continued and completed successfully. Native CLI duration substitutes for unavailable wrapper wall time; it does not include wrapper setup/teardown. No generation was repeated and no generated source was edited.",
  "instruction_source" => "Exact prompt from the recorded invocation, checked against QT-clustering OpenMP r1; the frozen prompt depends only on benchmark and backend.",
  "usage_source" => "Exact native terminal result; pre-run quota unavailable (HTTP 429), as recorded in the generation log.",
  "original_artifact_sha256" => incident.fetch("workspace_files").transform_values { |data| data.fetch("sha256") },
  "metadata_sha256" => ClaudeGenerationRecovery::METADATA.to_h { |name| [name, Digest::SHA256.file(File.join(directory, name)).hexdigest] } }
File.write(File.join(directory, ClaudeGenerationRecovery::FILENAME), JSON.pretty_generate(record) + "\n")
arguments = { model: manifest.fetch("invoked_model"), version: manifest.fetch("claude_version"),
  timeout_seconds: manifest.fetch("per_run_timeout_seconds"), baseline: baseline, batch: manifest.fetch("campaign_id") }
report = ClaudeGenerationObservation.read(directory, **arguments)
raise "Recovered totals differ" unless report.fetch("total_tokens") == 322573 && report.fetch("raw_total_seconds") == 865.229 && report.fetch("retry_count").zero?
pipeline = LocalEvaluation::AggregatePipeline.allocate
pipeline.instance_variable_set(:@warnings, {})
pipeline.define_singleton_method(:apply_diff_counts) { |*_args| }
aggregate = AggregateEvaluation.new("qtclustering", manifest.fetch("model"), "omp", 2)
pipeline.send(:parse_agent_metadata, id, { "source_path" => directory, "batch" => manifest.fetch("campaign_id") }, aggregate)
raise "Aggregate recovery differs" unless aggregate.total_time == 865.229 && aggregate.api_time == 61.451 &&
  aggregate.total_tokens == 322573 && aggregate.generation_time_recovered == true && aggregate.wrapper_exit_status_available == false

canonical = File.join(results, id)
raise "Canonical target already exists" if File.exist?(canonical)
raise "Account became busy" unless GenerationCleanup.new.pids.empty?
# Move the original out of llmtest's reach, as the normal wrapper would have done.
# Its independent incident copy remains unchanged; no original file is deleted.
FileUtils.mv(workspace, canonical)
%w[instruction.txt timing.txt process-status.txt usage.txt generation-recovery.txt].each do |name|
  raise "Unexpected existing metadata" if File.exist?(File.join(canonical, name))
  FileUtils.cp(File.join(directory, name), File.join(canonical, name))
end
raise "Canonical recovery differs" unless ClaudeGenerationObservation.read(canonical, **arguments) == report
GenerationCampaign.new(root).observation(id, baseline: baseline)
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true)
completed = Dir.children(results)
pending = ids - completed
raise "Resume scope differs" unless completed.size == 51 && pending.size == 169 && pending.first == "roomsim_claude-sonnet-5.5-cc-medium_omp_r2"
FileUtils.cp(__FILE__, File.join(incident_root, File.basename(__FILE__)))
File.write(receipt_path, JSON.pretty_generate({ "recovered_at" => Time.now.utc.iso8601, "run_id" => id,
  "canonical_directory" => canonical, "source_and_transcript_unchanged" => true, "no_generation_repeated" => true,
  "original_workspace_moved_out_of_evaluation_account" => !File.exist?(workspace),
  "prior_observations_unchanged" => prior.size, "completed" => completed.size, "unstarted" => pending.size,
  "next_id" => pending.first, "recovery_metadata_sha256" => Digest::SHA256.file(File.join(canonical, ClaudeGenerationRecovery::FILENAME)).hexdigest,
  "observation" => report, "aggregate_metadata_check" => "passed", "staging_directory" => staging,
  "approval" => "User approved retaining this exact completed program with recovered native CLI duration, unknown wrapper status, OOMPolicy=continue, and resuming only unstarted observations." }) + "\n")
puts JSON.generate({ "recovered" => id, "completed" => completed.size, "unstarted" => pending.size, "next_id" => pending.first,
  "total_seconds" => report.fetch("total_seconds"), "total_tokens" => report.fetch("total_tokens"), "receipt" => receipt_path })
