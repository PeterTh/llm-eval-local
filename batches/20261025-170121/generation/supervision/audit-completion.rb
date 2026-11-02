# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"
require "/home/petert/llm_eval/experiment/lib/local_evaluation"
require "/home/petert/llm_eval/experiment/lib/generation_cleanup"

def git(repository, *arguments)
  output, error, status = Open3.capture3("git", "-C", repository, *arguments)
  raise "git failed: #{error}" unless status.success?
  output
end
root = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium"
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
excluded = /\A(?:build(?:[-_].*)?|cmake-build-.*|bin|CMakeFiles|node_modules|\.git(?:\.agent-backup)?)\z/i
extensions = %w[.txt .log .cpp .cu .h .hpp .inc .c .cc .cuh]
entries = git(repository, "ls-tree", "-r", "-l", "-z", commit, "--", batch).split("\0").map do |line|
  attributes, path = line.split("\t", 2)
  mode, type, oid, size = attributes.split
  raise "Nonregular artifact: #{path}" unless %w[100644 100755].include?(mode) && type == "blob"
  raise "Build/repository artifact: #{path}" if path.split("/").any? { |part| part.match?(excluded) }
  raise "Unexpected extension: #{path}" unless extensions.include?(File.extname(path))
  magic = File.binread(File.join(repository, path), 4)
  raise "Binary retained: #{path}" if magic == "\x7fELF" || magic.start_with?("MZ", "PK\x03\x04")
  { "path" => path, "bytes" => Integer(size), "git_blob" => oid }
end
tracked = entries.map { |entry| entry.fetch("path") }
Dir.glob(File.join(results, "**", "*"), File::FNM_DOTMATCH).each do |path|
  next unless File.file?(path) && !File.symlink?(path)
  relative = path.delete_prefix(repository + "/")
  next if relative.split("/").any? { |part| part.match?(excluded) }
  next unless extensions.include?(File.extname(path))
  raise "Output program/metadata silently ignored: #{relative}" unless tracked.include?(relative)
end
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflights").first
aggregate = LocalEvaluation::AggregatePipeline.allocate
aggregate.instance_variable_set(:@warnings, {})
aggregate.instance_variable_set(:@manifest, Struct.new(:benchmarks_root).new(File.join(manifest.fetch("runtime_root"), "benchmarks")))
profile = manifest.fetch("models").fetch("beam-1.0-oc-medium")
reports = ids.map do |id|
  source = File.join(results, id)
  report = OpenCodeGenerationObservation.read(source, model: profile.fetch("model"), effort: profile.fetch("reasoning_effort"),
    version: manifest.fetch("opencode_version"), baseline: baseline, timeout_seconds: manifest.fetch("per_run_timeout_seconds"))
  raise "Saved observation differs: #{id}" unless report == JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  report.fetch("sha256").each_key { |name| raise "Metadata not retained: #{id}/#{name}" unless tracked.include?("#{batch}/#{id}/#{name}") }
  raise "Cleanup failed: #{id}" unless JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json"))).fetch("verified_empty")
  benchmark, model, backend, repetition = id.split("_")
  parsed = AggregateEvaluation.new(benchmark, model, backend, repetition.delete_prefix("r").to_i)
  aggregate.send(:parse_agent_metadata, id, { "source_path" => source, "benchmark" => benchmark, "batch" => batch }, parsed)
  counts = report.fetch("token_counts")
  expected = {
    "total_time" => report.fetch("total_seconds"), "raw_total_time" => report.fetch("raw_total_seconds"), "api_time" => nil,
    "agent_retry_count" => report.fetch("retry_count"), "agent_retry_backoff_seconds" => report.fetch("retry_backoff_seconds"),
    "token_usage_source" => report.fetch("usage_source"), "token_usage_session_id" => report.fetch("session_id"),
    "token_usage_complete" => report.fetch("usage_complete"), "generation_outcome" => report.fetch("outcome"),
    "generation_failure_reason" => report["generation_failure_reason"], "termination_record_sha256" => report["termination_record_sha256"],
    "partial_token_counts" => report.fetch("usage_complete") ? nil : counts
  }
  { "input_tokens" => "input_tokens", "output_tokens" => "output_tokens", "cached_tokens" => "cached_input_tokens",
    "cache_write_input_tokens" => "cache_write_input_tokens", "reasoning_output_tokens" => "reasoning_output_tokens", "total_tokens" => "total_tokens" }.each do |field, key|
    expected[field] = report.fetch("usage_complete") ? counts.fetch(key) : nil
  end
  raise "Aggregate accounting differs: #{id}" unless expected.all? { |field, value| parsed.public_send(field) == value }
  raise "Metadata forced a validation decision" unless parsed.validation_status.nil?
  report
end
raise "Aggregate metadata warnings" unless aggregate.instance_variable_get(:@warnings).empty?
launches = File.read(File.join(manifest.fetch("queue_root"), "generation.log")).scan(/^Launching ([a-zA-Z0-9_.-]+) at /).flatten
  .select { |id| id.split("_")[1] == "beam-1.0-oc-medium" }
raise "Generation repeated or missing" unless launches.sort == ids && launches.uniq == launches
raise "Pilot launch order differs" unless launches.take(4) == manifest.fetch("preflight_ids")
raise "Pilot reuse differs" unless JSON.parse(File.read(File.join(root, "preflight-review.json"))).fetch("original_results_reused")
raise "Session reused" unless reports.map { |row| row.fetch("session_id") }.uniq.size == ids.size
reports.each do |row|
  raise "Output policy changed" unless row.fetch("output_token_policy") == manifest.fetch("opencode_output_token_policy")
  raise "Isolation policy changed" unless row.dig("filesystem_isolation", "policy") == manifest.fetch("generation_filesystem_policy")
end
original = JSON.parse(File.read(File.join(root, "incidents/20261029-prompt-rendering-failure/review.json")))
original.fetch("accepted_observation_sha256").each { |name, sha| raise "Prior report changed" unless Digest::SHA256.file(File.join(root, "observations", name)).hexdigest == sha }
original.fetch("affected_output_sha256").each { |name, sha| raise "Original failed attempt changed" unless Digest::SHA256.file(File.join(results, original.fetch("id"), name)).hexdigest == sha }
fable = manifest.fetch("paused_campaign").fetch("path")
raise "Fable STOP absent" unless File.file?(File.join(fable, "STOP"))
raise "Fable observation count changed" unless Dir[File.join(fable, "observations/*.json")].size == 139
complete, partial = reports.partition { |row| row.fetch("usage_complete") }
report = {
  "checked_at" => Time.now.utc.iso8601, "campaign_id" => batch, "source_commit" => commit,
  "source_repository" => repository, "source_branch" => manifest.fetch("source_branch"), "pushed" => false,
  "observations" => reports.size, "outcomes" => reports.group_by { |row| row.fetch("outcome") }.transform_values(&:size),
  "tracked_files" => entries.size, "uncompressed_bytes" => entries.sum { |entry| entry.fetch("bytes") },
  "verified_metadata_sha256_fingerprints" => reports.sum { |row| row.fetch("sha256").size },
  "native_cleanup_receipts" => ids.size, "accepted_generation_invocations" => launches.size,
  "retry_count" => reports.sum { |row| row.fetch("retry_count") },
  "retry_backoff_seconds" => reports.sum { |row| row.fetch("retry_backoff_seconds") }.round(6),
  "raw_generation_seconds" => reports.sum { |row| row.fetch("raw_total_seconds") }.round(6),
  "generation_seconds" => reports.sum { |row| row.fetch("total_seconds") }.round(6),
  "mean_generation_minutes" => reports.sum { |row| row.fetch("total_seconds") } / reports.size / 60,
  "total_reported_tokens_lower_bound" => reports.sum { |row| row.fetch("total_tokens") },
  "complete_usage_observations" => complete.size, "complete_observation_tokens" => complete.sum { |row| row.fetch("total_tokens") },
  "partial_usage" => partial.map { |row| row.slice("id", "generation_failure_reason", "token_counts", "termination_record_sha256") },
  "usage_complete" => partial.empty?, "paused_fable_observations" => 139,
  "checks_passed" => ["Original code and metadata committed with no binary/build/subrepo artifacts", "Every observation read back identically",
    "Aggregate accounting reconciled, including partial counters without an invented complete cost or validation verdict",
    "All pilots reused once; exactly one generation per ID", "Original approved-failure files and114 earlier reports unchanged",
    "Frozen model/output/isolation policy verified; all cleanup receipts passed", "Fable remains held at139 observations"],
  "next_stage" => "Native validation, Luna-first static timing review/correction, then unchanged-size benchmarking and publication"
}
LocalEvaluation.atomic_write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(root, File.basename(__FILE__)))
puts JSON.pretty_generate(report)
