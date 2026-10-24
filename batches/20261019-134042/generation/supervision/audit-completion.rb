# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"
require "/tmp/opencode-go-output-limit-controller-20261021.F2iMc4/lib/local_evaluation"
require "/tmp/opencode-go-output-limit-controller-20261021.F2iMc4/lib/generation_cleanup"

def git(repository, *arguments)
  output, error, status = Open3.capture3("git", "-C", repository, *arguments)
  raise "git failed: #{error}" unless status.success?
  output
end

root = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
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
raise "Wrong source branch" unless git(repository, "branch", "--show-current").strip == manifest.fetch("source_branch")
raise "Batch worktree changed" unless git(repository, "status", "--porcelain", "--", batch).empty?
changed = git(repository, "diff-tree", "--no-commit-id", "--name-only", "-r", commit).lines.map(&:strip)
raise "Commit scope differs" unless !changed.empty? && changed.all? { |path| path.start_with?(batch + "/") }
entries = git(repository, "ls-tree", "-r", "-l", "-z", commit, "--", batch).split("\0").map do |line|
  attributes, path = line.split("\t", 2)
  mode, type, oid, size = attributes.split
  raise "Nonregular retained artifact: #{path}" unless %w[100644 100755].include?(mode) && type == "blob"
  raise "Build or repository artifact retained: #{path}" if path.split("/").any? { |part| part.match?(/\A(?:build(?:[-_].*)?|cmake-build-.*|bin|CMakeFiles|node_modules|\.git(?:\.agent-backup)?)\z/i) }
  raise "Unexpected artifact extension: #{path}" unless %w[.txt .log .cpp .cu .h .hpp .inc .c .cc .cuh].include?(File.extname(path))
  magic = File.binread(File.join(repository, path), 4)
  raise "Executable/binary artifact retained: #{path}" if magic == "\x7fELF" || magic.start_with?("MZ", "PK\x03\x04")
  { "path" => path, "bytes" => Integer(size), "git_blob" => oid }
end
tracked = entries.map { |entry| entry.fetch("path") }
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflights").first
aggregate = LocalEvaluation::AggregatePipeline.allocate
aggregate.instance_variable_set(:@warnings, {})
aggregate.instance_variable_set(:@manifest, Struct.new(:benchmarks_root).new(File.join(manifest.fetch("runtime_root"), "benchmarks")))
profile = manifest.fetch("models").fetch("deepseek-v4.1-flash-oc-high")
required_count = 0
reports = ids.map do |id|
  source = File.join(results, id)
  report = OpenCodeGenerationObservation.read(source, model: profile.fetch("model"), effort: profile.fetch("reasoning_effort"),
    version: manifest.fetch("opencode_version"), baseline: baseline, timeout_seconds: manifest.fetch("per_run_timeout_seconds"))
  raise "Saved observation differs: #{id}" unless report == JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  required = %w[output.txt timing.txt instruction.txt process-status.txt] + OpenCodeHarness::EVIDENCE_FILES
  if report.fetch("outcome") == "generation_model_terminated"
    required.delete("opencode-process.txt")
    required << OpenCodeGenerationTermination::FILENAME
  end
  required.each { |name| raise "Metadata not retained: #{id}/#{name}" unless tracked.include?("#{batch}/#{id}/#{name}") }
  required_count += required.size
  cleanup = JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json")))
  raise "Cleanup failed for #{id}" unless cleanup.fetch("verified_empty")
  benchmark, model, backend, repetition = id.split("_")
  parsed = AggregateEvaluation.new(benchmark, model, backend, repetition.delete_prefix("r").to_i)
  aggregate.send(:parse_agent_metadata, id, { "source_path" => source, "benchmark" => benchmark, "batch" => batch }, parsed)
  counts = report.fetch("token_counts")
  expected = {
    "total_time" => report.fetch("total_seconds"), "raw_total_time" => report.fetch("raw_total_seconds"), "api_time" => nil,
    "agent_retry_count" => report.fetch("retry_count"), "agent_retry_backoff_seconds" => report.fetch("retry_backoff_seconds"),
    "token_usage_source" => report.fetch("usage_source"), "token_usage_session_id" => report.fetch("session_id"),
    "token_usage_complete" => report.fetch("usage_complete"), "generation_outcome" => report.fetch("outcome")
  }
  token_fields = { "input_tokens" => "input_tokens", "output_tokens" => "output_tokens", "cached_tokens" => "cached_input_tokens",
    "cache_write_input_tokens" => "cache_write_input_tokens", "reasoning_output_tokens" => "reasoning_output_tokens", "total_tokens" => "total_tokens" }
  token_fields.each { |field, key| expected[field] = report.fetch("usage_complete") ? counts.fetch(key) : nil }
  expected["partial_token_counts"] = counts unless report.fetch("usage_complete")
  raise "Aggregate accounting differs: #{id}" unless expected.all? { |field, value| parsed.public_send(field) == value }
  report
end
raise "Aggregate metadata warnings" unless aggregate.instance_variable_get(:@warnings).empty?
raise "Session reused" unless reports.map { |row| row.fetch("session_id") }.uniq.size == 220

amendment_root = manifest.fetch("runtime_amendment").fetch("path")
amendment = JSON.parse(File.read(File.join(amendment_root, "amendment.json")))
unchanged = JSON.parse(File.read(File.join(amendment_root, "unchanged-observations.json")))
raise "Unchanged scope differs" unless unchanged.size == 109
unchanged.each do |id, report|
  raise "Unchanged observation altered: #{id}" unless JSON.parse(File.read(File.join(root, "observations", "#{id}.json"))) == report
end
affected = amendment.fetch("affected_observations")
raise "Amendment scope differs" unless affected.size == 4 && (affected & unchanged.keys).empty?
reports.reject { |row| unchanged.key?(row.fetch("id")) }.each do |row|
  raise "Advertised output allowance not used" unless row.fetch("output_token_policy") == manifest.fetch("opencode_output_token_policy")
end
amendment.fetch("superseded_file_hashes").each do |id, files|
  files.each do |name, sha|
    path = File.join(amendment.fetch("superseded_attempts"), id, name)
    content = git(repository, "show", "#{amendment.fetch('superseded_source_commit')}:#{path}")
    raise "Superseded evidence changed: #{path}" unless Digest::SHA256.hexdigest(content) == sha
  end
end
queue_root = manifest.fetch("queue_root")
launches = File.read(File.join(queue_root, "generation.log")).scan(/^Launching ([a-zA-Z0-9_.-]+) at /).flatten
infrastructure = JSON.parse(File.read(File.join(root, "incidents/20261021-initial-503/incident.json")))
raise "Infrastructure start classification differs" unless infrastructure.fetch("classification") == "provider_unavailable_before_any_model_output" &&
  infrastructure.fetch("model_tool_calls").zero? && infrastructure.fetch("native_completed_request_tokens").zero?
expected_launches = (ids + affected + [infrastructure.fetch("run_id")]).tally
raise "Unexpected repeated or missing generation" unless launches.tally == expected_launches
preflight_ids = manifest.fetch("preflight_ids")
raise "Preflights repeated" unless preflight_ids.all? { |id| launches.count(id) == 1 }
raise "Preflight reuse differs" unless JSON.parse(File.read(File.join(root, "preflight-review.json"))).fetch("original_results_reused")
partial = reports.reject { |row| row.fetch("usage_complete") }
raise "Unexpected incomplete usage" unless partial.map { |row| row.fetch("id") }.sort == %w[
  qtclustering_deepseek-v4.1-flash-oc-high_mpi_r2
  qtclustering_deepseek-v4.1-flash-oc-high_hybrid_r4
  qtclustering_deepseek-v4.1-flash-oc-high_hybrid_r5
].sort && partial.all? { |row| row.fetch("outcome") == "generation_model_terminated" }
raise "Terminated generation repeated" unless partial.all? { |row| launches.count(row.fetch("id")) == 1 }

fable = manifest.fetch("paused_campaign").fetch("path")
pause_path = File.join(fable, "operator-pause-20261017.json")
raise "Fable pause receipt changed" unless Digest::SHA256.file(pause_path).hexdigest == manifest.fetch("paused_campaign").fetch("pause_receipt_sha256")
pause = JSON.parse(File.read(pause_path))
raise "Fable STOP guard absent" unless File.file?(File.join(fable, "STOP"))
pause.fetch("observation_sha256").each do |name, sha|
  raise "Fable evidence changed: #{name}" unless Digest::SHA256.file(File.join(fable, "observations", name)).hexdigest == sha
end
minimax = JSON.parse(File.read(File.join(queue_root, "queue.json"))).fetch("campaigns").last
raise "MiniMax hold missing" unless File.file?(File.join(minimax, "STOP"))
raise "MiniMax started" unless Dir[File.join(minimax, "observations/*.json")].empty?
report = {
  "checked_at" => Time.now.utc.iso8601, "campaign_id" => batch, "source_commit" => commit,
  "source_repository" => repository, "source_branch" => manifest.fetch("source_branch"), "pushed" => false,
  "observations" => reports.size, "outcomes" => reports.group_by { |row| row.fetch("outcome") }.transform_values(&:size),
  "tracked_files" => entries.size, "uncompressed_bytes" => entries.sum { |entry| entry.fetch("bytes") },
  "required_metadata_files" => required_count, "verified_metadata_sha256_fingerprints" => reports.sum { |row| row.fetch("sha256").size },
  "native_cleanup_receipts" => ids.size, "total_generation_invocations" => launches.size,
  "accepted_generation_invocations" => ids.size, "superseded_lower_output_cap_attempts" => affected,
  "unaccepted_zero_output_infrastructure_attempts" => 1, "unaffected_pre_amendment_observations_unchanged" => unchanged.size,
  "retry_count" => reports.sum { |row| row.fetch("retry_count") },
  "retry_backoff_seconds" => reports.sum { |row| row.fetch("retry_backoff_seconds") }.round(6),
  "raw_generation_seconds" => reports.sum { |row| row.fetch("raw_total_seconds") }.round(6),
  "generation_seconds" => reports.sum { |row| row.fetch("total_seconds") }.round(6),
  "mean_generation_minutes" => reports.sum { |row| row.fetch("total_seconds") } / reports.size / 60,
  "total_tokens_lower_bound" => reports.sum { |row| row.fetch("total_tokens") }, "usage_complete" => false,
  "incomplete_usage_observations" => partial.map { |row| row.slice("id", "total_tokens", "usage_complete", "outcome") },
  "aggregate_accounting" => "Full native counters exported only for complete attempts; interrupted attempts retain partial counters with complete-cost fields unset.",
  "paused_fable_observation_fingerprints_unchanged" => pause.fetch("observation_sha256").size,
  "minimax_held_without_generation" => true,
  "checks_passed" => ["All 220 originals committed; exact ID set and metadata retained", "Fresh native observation checker matches every saved report",
    "Independent aggregation agrees; partial usage cannot be mistaken for full-task cost", "Only authorized four output-limit replacements and one zero-output infrastructure retry",
    "All three model-caused terminations retained without retry or source edits", "No gitlinks, symlinks, build directories or executable binaries retained",
    "All four production pilots reused once", "Native cleanup verified; account currently empty", "Fable evidence and MiniMax hold preserved"],
  "next_stage" => "Native validation, source-only timing review/correction, then established-size benchmarking; Fable has priority at its quota reset."
}
LocalEvaluation.atomic_write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(root, "audit-completion.rb"))
puts JSON.pretty_generate(report)
