# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"
require "/tmp/haiku55-opencode-medium-generation-20261025-805219-3829u5/experiment/lib/local_evaluation"
require "/tmp/haiku55-opencode-medium-generation-20261025-805219-3829u5/experiment/lib/generation_cleanup"

def git(repository, *arguments)
  output, error, status = Open3.capture3("git", "-C", repository, *arguments)
  raise "git failed: #{error}" unless status.success?
  output
end

root = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium"
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
required = %w[output.txt timing.txt instruction.txt process-status.txt] + OpenCodeHarness::EVIDENCE_FILES
profile = manifest.fetch("models").fetch("claude-haiku-5.5-oc-medium")
reports = ids.map do |id|
  source = File.join(results, id)
  report = OpenCodeGenerationObservation.read(source, model: profile.fetch("model"), effort: profile.fetch("reasoning_effort"),
    version: manifest.fetch("opencode_version"), baseline: baseline, timeout_seconds: manifest.fetch("per_run_timeout_seconds"))
  raise "Saved observation differs: #{id}" unless report == JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  required.each { |name| raise "Metadata not retained: #{id}/#{name}" unless tracked.include?("#{batch}/#{id}/#{name}") }
  cleanup = JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json")))
  raise "Cleanup failed for #{id}" unless cleanup.fetch("verified_empty")
  benchmark, model, backend, repetition = id.split("_")
  parsed = AggregateEvaluation.new(benchmark, model, backend, repetition.delete_prefix("r").to_i)
  aggregate.send(:parse_agent_metadata, id, { "source_path" => source, "benchmark" => benchmark, "batch" => batch }, parsed)
  counts = report.fetch("token_counts")
  expected = {
    "total_time" => report.fetch("total_seconds"), "raw_total_time" => report.fetch("raw_total_seconds"), "api_time" => nil,
    "input_tokens" => counts.fetch("input_tokens"), "output_tokens" => counts.fetch("output_tokens"),
    "cached_tokens" => counts.fetch("cached_input_tokens"), "cache_write_input_tokens" => counts.fetch("cache_write_input_tokens"),
    "reasoning_output_tokens" => counts.fetch("reasoning_output_tokens"), "total_tokens" => report.fetch("total_tokens"),
    "agent_retry_count" => report.fetch("retry_count"), "agent_retry_backoff_seconds" => report.fetch("retry_backoff_seconds"),
    "token_usage_source" => report.fetch("usage_source"), "token_usage_session_id" => report.fetch("session_id")
  }
  raise "Aggregate accounting differs: #{id}" unless expected.all? { |field, value| parsed.public_send(field) == value }
  report
end
raise "Aggregate metadata warnings" unless aggregate.instance_variable_get(:@warnings).empty?
queue = manifest.fetch("queue_root")
launches = File.read(File.join(queue, "generation.log")).scan(/^Launching ([a-zA-Z0-9_.-]+) at /).flatten
preflight_ids = manifest.fetch("preflight_ids")
raise "Accepted generation repeated or missing" unless launches.sort == ids && launches.uniq == launches
raise "Preflight launch order differs" unless launches.take(4) == preflight_ids
raise "Preflight reuse differs" unless JSON.parse(File.read(File.join(root, "preflight-review.json"))).fetch("original_results_reused")
raise "Session reused" unless reports.map { |row| row.fetch("session_id") }.uniq.size == ids.size
reports.each do |row|
  raise "Output policy changed" unless row.fetch("output_token_policy") == manifest.fetch("opencode_output_token_policy")
  raise "Isolation policy changed" unless row.dig("filesystem_isolation", "policy") == manifest.fetch("generation_filesystem_policy")
end
fable = manifest.fetch("paused_campaign").fetch("path")
raise "Fable STOP absent" unless File.file?(File.join(fable, "STOP"))
fable_count = Dir[File.join(fable, "observations/*.json")].size
raise "Fable observation count changed" unless fable_count == 139
beam = JSON.parse(File.read(File.join(queue, "queue.json"))).fetch("campaigns").last
raise "Beam hold absent" unless File.file?(File.join(beam, "STOP"))
raise "Beam started" unless Dir[File.join(beam, "observations/*.json")].empty?
report = {
  "checked_at" => Time.now.utc.iso8601, "campaign_id" => batch, "source_commit" => commit,
  "source_repository" => repository, "source_branch" => manifest.fetch("source_branch"), "pushed" => false,
  "observations" => reports.size, "outcomes" => reports.group_by { |row| row.fetch("outcome") }.transform_values(&:size),
  "tracked_files" => entries.size, "uncompressed_bytes" => entries.sum { |entry| entry.fetch("bytes") },
  "required_metadata_files" => ids.size * required.size,
  "verified_metadata_sha256_fingerprints" => reports.sum { |row| row.fetch("sha256").size },
  "aggregate_accounting_fields_verified_per_observation" => 13,
  "native_cleanup_receipts" => ids.size,
  "accepted_generation_invocations" => launches.size,
  "unaccepted_infrastructure_pilot_attempts" => 0,
  "retry_count" => reports.sum { |row| row.fetch("retry_count") },
  "retry_backoff_seconds" => reports.sum { |row| row.fetch("retry_backoff_seconds") }.round(6),
  "raw_generation_seconds" => reports.sum { |row| row.fetch("raw_total_seconds") }.round(6),
  "generation_seconds" => reports.sum { |row| row.fetch("total_seconds") }.round(6),
  "mean_generation_minutes" => reports.sum { |row| row.fetch("total_seconds") } / reports.size / 60,
  "total_tokens" => reports.sum { |row| row.fetch("total_tokens") },
  "usage_complete" => reports.all? { |row| row.fetch("usage_complete") },
  "paused_fable_observations" => fable_count, "beam_held_without_generation" => true,
  "checks_passed" => ["Exact original ID set and metadata retained", "Fresh observation checker matches every saved report",
    "Independent aggregate entry point matches without warnings", "Native SSE and session accounting counters agree; CLI omissions are terminal only",
    "Only this batch committed; worktree unchanged", "No gitlinks, symlinks, build directories or executable binaries retained",
    "All four production pilots reused once; no unaccepted infrastructure attempts",
    "Native cleanup verified; account currently empty", "Fable STOP and observation count preserved; Beam held without inference"],
  "next_stage" => "Native validation, source-only timing review/correction, then established-size benchmarking"
}
LocalEvaluation.atomic_write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(root, File.basename(__FILE__)))
puts JSON.pretty_generate(report)
