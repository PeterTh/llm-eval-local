require "json"
require "digest"
require "open3"
require "fileutils"
require "time"
require "/home/petert/llm_eval/experiment/lib/claude_generation_observation"
require "/home/petert/llm_eval/experiment/lib/local_evaluation"
require "/home/petert/llm_eval/experiment/lib/generation_cleanup"

def git(repository, *arguments)
  output, error, status = Open3.capture3("git", "-C", repository, *arguments)
  raise "git failed: #{error}" unless status.success?
  output
end

root = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium"
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
completion = JSON.parse(File.read(File.join(root, "completion.json")))
target = File.join(root, "completion-audit.json")
raise "Audit already exists" if File.exist?(target)
raise "Account not idle" unless GenerationCleanup.new.pids.empty?
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true).sort
results = manifest.fetch("persistent_results")
repository = File.dirname(results)
batch = manifest.fetch("campaign_id")
commit = completion.fetch("source_commit")
raise "Completion scope differs" unless completion.fetch("observations") == 220 && Dir.children(results).sort == ids
raise "Source commit differs" unless git(repository, "rev-parse", "HEAD").strip == commit
raise "Wrong source branch" unless git(repository, "branch", "--show-current").strip == "claude"
raise "Batch worktree changed" unless git(repository, "status", "--porcelain", "--", batch).empty?
changed = git(repository, "diff-tree", "--no-commit-id", "--name-only", "-r", commit).lines.map(&:strip)
raise "Commit scope differs" unless !changed.empty? && changed.all? { |path| path.start_with?(batch + "/") }
entries = git(repository, "ls-tree", "-r", "-l", "-z", commit, "--", batch).split("\0").map do |line|
  attributes, path = line.split("\t", 2)
  mode, type, oid, size = attributes.split
  raise "Nonregular retained artifact: #{path}" unless %w[100644 100755].include?(mode) && type == "blob"
  raise "Build or repository artifact retained: #{path}" if path.split("/").any? { |part| part.match?(/\A(?:build(?:[-_].*)?|cmake-build-.*|bin|CMakeFiles|\.git(?:\.agent-backup)?)\z/i) }
  raise "Unexpected artifact extension: #{path}" unless %w[.txt .log .cpp .cu .h .hpp .inc].include?(File.extname(path))
  magic = File.binread(File.join(repository, path), 4)
  raise "Executable/binary artifact retained: #{path}" if magic == "\x7fELF" || magic.start_with?("MZ", "PK\x03\x04")
  { "path" => path, "bytes" => Integer(size), "git_blob" => oid }
end
tracked = entries.map { |entry| entry.fetch("path") }
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflight")
aggregate = LocalEvaluation::AggregatePipeline.allocate
aggregate.instance_variable_set(:@warnings, {})
aggregate.instance_variable_set(:@manifest, Struct.new(:benchmarks_root).new(File.join(manifest.fetch("runtime_root"), "benchmarks")))
recovered_id = "qtclustering_claude-sonnet-5.5-cc-medium_omp_r2"
recovery = JSON.parse(File.read(File.join(root, "incidents/20261015-oom/recovery.json")))
incident = JSON.parse(File.read(File.join(root, "incidents/20261015-oom/incident.json")))
reports = ids.map do |id|
  source = File.join(results, id)
  report = ClaudeGenerationObservation.read(source, model: manifest.fetch("invoked_model"), version: manifest.fetch("claude_version"),
    baseline: baseline, batch: batch, timeout_seconds: manifest.fetch("per_run_timeout_seconds"))
  raise "Saved observation differs: #{id}" unless report == JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  required = %w[output.txt timing.txt instruction.txt process-status.txt usage.txt]
  required << "generation-recovery.txt" if id == recovered_id
  required.each { |name| raise "Metadata not retained: #{id}/#{name}" unless tracked.include?("#{batch}/#{id}/#{name}") }
  if id == recovered_id
    raise "Recovery account verification absent" unless incident.fetch("account_verified_idle") && recovery.fetch("original_workspace_moved_out_of_evaluation_account")
  else
    cleanup = JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json")))
    raise "Cleanup failed for #{id}" unless cleanup.fetch("verified_empty")
  end
  benchmark, model, backend, repetition = id.split("_")
  parsed = AggregateEvaluation.new(benchmark, model, backend, repetition.delete_prefix("r").to_i)
  aggregate.send(:parse_agent_metadata, id, { "source_path" => source, "benchmark" => benchmark, "batch" => batch }, parsed)
  expected = { "total_time" => report.fetch("total_seconds"), "api_time" => report.fetch("api_seconds"),
    "input_tokens" => report.fetch("inclusive_input_tokens"), "output_tokens" => report.fetch("token_counts").fetch("output_tokens"),
    "cached_tokens" => report.fetch("token_counts").fetch("cache_read_input_tokens"), "total_tokens" => report.fetch("total_tokens"),
    "agent_retry_count" => report.fetch("retry_count"), "agent_retry_backoff_seconds" => report.fetch("retry_backoff_seconds") }
  raise "Aggregate accounting differs: #{id}" unless expected.all? { |field, value| parsed.public_send(field) == value }
  if id == recovered_id
    raise "Recovery label lost" unless parsed.generation_time_recovered == true && parsed.wrapper_exit_status_available == false &&
      parsed.generation_time_source == report.fetch("generation_time_source") && parsed.generation_recovery_sha256 == report.fetch("generation_recovery_sha256")
  else
    raise "Unexpected recovery label" if parsed.generation_time_recovered
  end
  report
end
raise "Aggregate metadata warnings: #{aggregate.instance_variable_get(:@warnings)}" unless aggregate.instance_variable_get(:@warnings).empty?
log = File.read(File.join(root, "generation.log"))
launches = log.scan(/^Launching ([a-zA-Z0-9_.-]+) at /).flatten
preflight_ids = manifest.fetch("preflight_ids")
raise "Generation repeated or missing" unless launches.sort == (ids - preflight_ids).sort && launches.uniq == launches
raise "Preflight reuse differs" unless JSON.parse(File.read(File.join(root, "preflight-review.json"))).fetch("original_result_reused")
fable = manifest.fetch("paused_campaign").fetch("path")
pause = JSON.parse(File.read(File.join(fable, "operator-pause.json")))
raise "Fable STOP guard absent" unless File.file?(File.join(fable, "STOP"))
pause.fetch("observation_sha256").each do |name, digest|
  raise "Fable evidence changed: #{name}" unless Digest::SHA256.file(File.join(fable, "observations", name)).hexdigest == digest
end
report = { "checked_at" => Time.now.utc.iso8601, "campaign_id" => batch, "source_commit" => commit,
  "source_repository" => repository, "source_branch" => "claude", "pushed" => false,
  "observations" => reports.size, "outcomes" => reports.group_by { |row| row.fetch("outcome") }.transform_values(&:size),
  "tracked_files" => entries.size, "uncompressed_bytes" => entries.sum { |entry| entry.fetch("bytes") },
  "required_metadata_files" => ids.size * 5 + 1, "verified_metadata_sha256_fingerprints" => reports.sum { |row| row.fetch("sha256").size },
  "aggregate_accounting_fields_verified_per_observation" => 8, "recovered_generation_observations" => [recovered_id],
  "recovery_provenance_fields_verified" => 4, "native_cleanup_receipts" => 219,
  "recovered_observation_account_idle_evidence" => "incidents/20261015-oom/incident.json and recovery.json; both before resuming",
  "generation_invocations" => launches.size + preflight_ids.size,
  "retry_count" => reports.sum { |row| row.fetch("retry_count") }, "retry_backoff_seconds" => reports.sum { |row| row.fetch("retry_backoff_seconds") },
  "generation_seconds" => reports.sum { |row| row.fetch("total_seconds") },
  "mean_generation_minutes" => reports.sum { |row| row.fetch("total_seconds") } / reports.size / 60,
  "total_tokens" => reports.sum { |row| row.fetch("total_tokens") },
  "paused_fable_observation_fingerprints_unchanged" => pause.fetch("observation_sha256").size,
  "checks_passed" => ["Exact original ID set and metadata retained", "Fresh observation checker matches every saved report",
    "Independent aggregate parser matches without warnings", "Recovered native duration and unknown wrapper status remain explicitly labeled",
    "Only this batch committed; worktree unchanged", "No gitlinks, symlinks, build directories or executable binaries retained",
    "Exactly one generation invocation per ID", "Native cleanup and recovered account-idle checks verified; account currently empty",
    "Paused Fable observations and STOP guard preserved"],
  "next_stage" => "Native validation, source-only timing review/correction, then established-size benchmarking" }
File.write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(root, File.basename(__FILE__)))
puts JSON.pretty_generate(report)
