# frozen_string_literal: true

require "json"
require "digest"
require "open3"
require "time"
require "fileutils"

$stdout.sync = true
root = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
completion = JSON.parse(File.read(File.join(root, "completion.json")))
repository = "/home/petert/llm_para_experiments"
batch = manifest.fetch("campaign_id")
commit = completion.fetch("source_commit")
require File.join(manifest.fetch("working_directory"), "lib/local_evaluation")
require File.join(manifest.fetch("working_directory"), "lib/claude_generation_observation")
git = lambda do |*args|
  out, err, status = Open3.capture3("git", "-C", repository, *args)
  raise "Git failed: #{args.inspect}: #{err}" unless status.success?
  out
end
raise "Source HEAD changed" unless git.call("rev-parse", "HEAD").strip == commit
raise "Batch worktree changed" unless git.call("status", "--porcelain", "--", batch).empty?
changed = git.call("diff-tree", "--no-commit-id", "--name-only", "-r", "-z", commit).split("\0")
raise "Commit contains another batch" unless changed.all? { |p| p.start_with?("#{batch}/") }
entries = git.call("ls-tree", "-r", "-z", "-l", commit, "--", batch).split("\0").map do |entry|
  info, path = entry.split("\t", 2)
  mode, type, object, size = info.split
  raise "Non-regular entry #{path}" unless type == "blob" && %w[100644 100755].include?(mode)
  raise "Reproducible artifact retained: #{path}" if path.split("/").any? { |part| %w[.git build CMakeFiles node_modules .venv].include?(part) }
  magic = File.binread(File.join(repository, path), 4)
  raise "Executable binary retained: #{path}" if magic.start_with?("\x7fELF".b, "MZ".b)
  [path, size.to_i, object]
end
tracked = entries.map(&:first)
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true).sort
raise "Wrong requested ID count" unless ids.size == 220 && ids.uniq == ids
raise "Unexpected committed IDs" unless tracked.map { |p| p.split("/")[1] }.uniq.sort == ids
raise "Unexpected observed IDs" unless Dir[File.join(root, "observations", "*.json")].map { |p| File.basename(p, ".json") }.sort == ids
metadata = %w[output.txt timing.txt instruction.txt process-status.txt usage.txt]
fingerprints = 0
reports = ids.map do |id|
  source = File.join(repository, batch, id)
  metadata.each { |name| raise "Missing retained metadata #{id}/#{name}" unless tracked.include?("#{batch}/#{id}/#{name}") }
  report = JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  fresh = ClaudeGenerationObservation.read(source, model: manifest.fetch("invoked_model"), version: manifest.fetch("claude_version"))
  raise "Observation changed: #{id}" unless fresh == report
  fingerprints += report.fetch("sha256").size
  cleanup = JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json")))
  raise "Cleanup unverified: #{id}" unless cleanup.fetch("verified_empty")
  benchmark, model, backend, repetition = id.split("_")
  result = AggregateEvaluation.new(benchmark, model, backend, repetition.delete_prefix("r").to_i)
  parser = LocalEvaluation::AggregatePipeline.allocate
  parser.instance_variable_set(:@warnings, {})
  parser.instance_variable_set(:@manifest, Struct.new(:benchmarks_root).new(File.join(__dir__, "benchmarks")))
  parser.send(:parse_agent_metadata, id, { "source_path" => source, "benchmark" => benchmark }, result)
  expected = { "total_time" => report.fetch("total_seconds"), "api_time" => report.fetch("api_seconds"),
    "input_tokens" => report.fetch("inclusive_input_tokens"), "output_tokens" => report.fetch("token_counts").fetch("output_tokens"),
    "cached_tokens" => report.fetch("token_counts").fetch("cache_read_input_tokens"), "total_tokens" => report.fetch("total_tokens"),
    "agent_retry_count" => report.fetch("retry_count"), "agent_retry_backoff_seconds" => report.fetch("retry_backoff_seconds") }
  raise "Aggregate accounting disagrees: #{id}" unless expected.all? { |key, value| result.public_send(key) == value }
  raise "Aggregate warning: #{id}" unless parser.instance_variable_get(:@warnings).empty?
  report
end
logs = %w[preflight.log generation.log].map { |name| File.read(File.join(root, name)) }.join("\n")
launches = logs.lines.filter_map { |line| line.match(/\ACommand for (.+):\s*\z/)&.captures&.first }
raise "Repeated or missing generation invocation" unless launches.sort == ids
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Account is not empty" unless status.exitstatus == 1 && pids.empty?
fable = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium"
pause = JSON.parse(File.read(File.join(fable, "operator-pause.json")))
pause.fetch("observation_sha256").each do |name, sha|
  raise "Paused Fable observation changed: #{name}" unless Digest::SHA256.file(File.join(fable, "observations", name)).hexdigest == sha
end
raise "Fable STOP guard missing" unless File.file?(File.join(fable, "STOP"))
report = {
  "checked_at" => Time.now.utc.iso8601, "campaign_id" => batch, "source_commit" => commit,
  "source_repository" => repository, "source_branch" => git.call("branch", "--show-current").strip,
  "pushed" => false, "observations" => reports.size,
  "outcomes" => reports.group_by { |r| r.fetch("outcome") }.transform_values(&:size),
  "tracked_files" => entries.size, "uncompressed_bytes" => entries.sum { |e| e[1] },
  "required_metadata_files" => ids.size * metadata.size,
  "verified_metadata_sha256_fingerprints" => fingerprints,
  "aggregate_accounting_fields_verified_per_observation" => 8,
  "generation_invocations" => launches.size, "retry_count" => reports.sum { |r| r.fetch("retry_count") },
  "retry_backoff_seconds" => reports.sum { |r| r.fetch("retry_backoff_seconds") },
  "generation_seconds" => reports.sum { |r| r.fetch("total_seconds") },
  "mean_generation_minutes" => reports.sum { |r| r.fetch("total_seconds") } / reports.size / 60,
  "total_tokens" => reports.sum { |r| r.fetch("total_tokens") },
  "paused_fable_observation_fingerprints_unchanged" => pause.fetch("observation_sha256").size,
  "checks_passed" => ["Exact original ID set and metadata retained", "Fresh observation checker matches every saved report",
    "Independent aggregate parser matches without warnings", "Only this batch committed; worktree unchanged",
    "No gitlinks, symlinks, build directories or executable binaries retained", "Exactly one generation invocation per ID",
    "All account cleanup verified and account currently empty", "Paused Fable observations and STOP guard preserved"],
  "next_stage" => "Native validation, then source-only timing review and established-size benchmarking"
}
target = File.join(root, "completion-audit.json")
raise "Completion audit already exists" if File.exist?(target)
LocalEvaluation.atomic_write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(root, File.basename(__FILE__)))
puts JSON.pretty_generate(report)
