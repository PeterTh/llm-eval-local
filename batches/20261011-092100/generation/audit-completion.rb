# frozen_string_literal: true
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
  raise "Git failed: #{arguments.first}: #{error}" unless status.success?
  output
end

root = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium"
target = File.join(root, "completion-audit.json")
previous_audit = nil
if ARGV == ["--correct-legacy-quota-log"]
  previous_audit = "5d8de9335544ef46a0c24e391cfc07104ab98b47979aee63c0732fba694cc096"
  raise "Initial audit differs" unless Digest::SHA256.file(target).hexdigest == previous_audit
  raise "Prior audit already preserved" if File.exist?(File.join(root, "completion-audit-before-legacy-quota-log.json"))
else
  raise "Unexpected arguments" unless ARGV.empty?
  raise "Audit already exists" if File.exist?(target)
end
raise "Account not idle" unless GenerationCleanup.new.pids.empty?
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
completion = JSON.parse(File.read(File.join(root, "completion.json")))
progress = JSON.parse(File.read(File.join(root, "progress.json")))
raise "Generation incomplete" unless progress.fetch("status") == "complete" && progress.fetch("completed") == 220
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true).sort
expected = manifest.fetch("benchmarks").product([manifest.fetch("model")], manifest.fetch("backends"), (1..5).to_a).map { |b, m, p, r| "#{b}_#{m}_#{p}_r#{r}" }
raise "Selection differs" unless ids.size == 220 && ids.uniq == ids && ids == expected.sort
results = manifest.fetch("persistent_results")
repository = File.dirname(results)
batch = manifest.fetch("campaign_id")
commit = completion.fetch("source_commit")
raise "Completion scope differs" unless completion.fetch("observations") == 220 && Dir.children(results).sort == ids
raise "Source commit differs" unless git(repository, "rev-parse", "HEAD").strip == commit
raise "Wrong source branch" unless git(repository, "branch", "--show-current").strip == "claude"
raise "Batch worktree changed" unless git(repository, "status", "--porcelain", "--", batch).empty?
changed = git(repository, "diff-tree", "--no-commit-id", "--name-only", "-z", "-r", commit).split("\0")
raise "Commit scope differs" unless !changed.empty? && changed.all? { |path| path.start_with?(batch + "/") }
entries = git(repository, "ls-tree", "-r", "-l", "-z", commit, "--", batch).split("\0").map do |line|
  attributes, path = line.split("\t", 2)
  mode, type, oid, size = attributes.split
  raise "Nonregular artifact: #{path}" unless %w[100644 100755].include?(mode) && type == "blob"
  raise "Build or repository artifact: #{path}" if path.split("/").any? { |part| part.match?(/\A(?:build(?:[-_].*)?|cmake-build-.*|bin|CMakeFiles|node_modules|\.git(?:\.agent-backup)?|\.hg|\.svn)\z/i) }
  raise "Unexpected extension: #{path}" unless %w[.txt .log .cpp .cu .h .hpp .inc .c .cc .cxx .cuh .hxx .inl .cmake].include?(File.extname(path))
  magic = File.binread(File.join(repository, path), 4)
  raise "Binary retained: #{path}" if magic.start_with?("\x7fELF".b, "MZ".b, "PK\x03\x04".b)
  { "path" => path, "bytes" => Integer(size), "git_blob" => oid }
end
tracked = entries.map { |entry| entry.fetch("path") }
raise "Tracked scope differs" unless tracked.map { |path| path.split("/")[1] }.uniq.sort == ids
ignored = git(repository, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z", "--", batch).split("\0")
raise "Potential source ignored" if ignored.any? { |path| path.match?(/\.(?:c|cc|cpp|cxx|cu|cuh|h|hpp|hxx|inl|inc|cmake)\z/i) }
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflight")
isolation = JSON.parse(File.read(File.join(root, "filesystem-isolation-20261024/cleanup-scope-fix.json")))
preserved = isolation.fetch("preserved_ids")
raise "Isolation boundary differs" unless preserved.size == 95
aggregate = LocalEvaluation::AggregatePipeline.allocate
aggregate.instance_variable_set(:@warnings, {})
aggregate.instance_variable_set(:@manifest, Struct.new(:benchmarks_root).new(File.join(manifest.fetch("runtime_root"), "benchmarks")))
reports = ids.to_h do |id|
  source = File.join(results, id)
  report = ClaudeGenerationObservation.read(source, model: manifest.fetch("invoked_model"), version: manifest.fetch("claude_version"),
    baseline: baseline, batch: batch, timeout_seconds: manifest.fetch("per_run_timeout_seconds"))
  raise "Saved observation differs: #{id}" unless report == JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  required = %w[output.txt timing.txt instruction.txt process-status.txt usage.txt]
  required << "claude-filesystem.txt" unless preserved.include?(id)
  required.each { |name| raise "Metadata not retained: #{id}/#{name}" unless tracked.include?("#{batch}/#{id}/#{name}") }
  raise "Isolation boundary changed: #{id}" unless report.key?("filesystem_isolation") == !preserved.include?(id)
  raise "Cleanup failed: #{id}" unless JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json"))).fetch("verified_empty")
  benchmark, model, backend, repetition = id.split("_")
  parsed = AggregateEvaluation.new(benchmark, model, backend, repetition.delete_prefix("r").to_i)
  aggregate.send(:parse_agent_metadata, id, { "source_path" => source, "benchmark" => benchmark, "batch" => batch }, parsed)
  expected_fields = { "total_time" => report.fetch("total_seconds"), "api_time" => report.fetch("api_seconds"),
    "input_tokens" => report.fetch("inclusive_input_tokens"), "output_tokens" => report.fetch("token_counts").fetch("output_tokens"),
    "cached_tokens" => report.fetch("token_counts").fetch("cache_read_input_tokens"), "total_tokens" => report.fetch("total_tokens"),
    "agent_retry_count" => report.fetch("retry_count"), "agent_retry_backoff_seconds" => report.fetch("retry_backoff_seconds") }
  raise "Aggregate accounting differs: #{id}" unless expected_fields.all? { |field, value| parsed.public_send(field) == value }
  raise "Unexpected recovery" if parsed.generation_time_recovered
  [id, report]
end
raise "Aggregate warnings" unless aggregate.instance_variable_get(:@warnings).empty?
sessions = reports.values.map { |report| report.fetch("session_id") }
raise "Reused accepted session" unless sessions.uniq == sessions
raise "Preflight not reused" unless JSON.parse(File.read(File.join(root, "preflight-review.json"))).fetch("original_result_reused")

log = File.binread(File.join(root, "generation.log"))
launch_positions = []
log.to_enum(:scan, /^Launching (\S+) at /).each { launch_positions << [Regexp.last_match.begin(0), Regexp.last_match[1]] }
launches = launch_positions.map(&:last)
preflight_ids = manifest.fetch("preflight_ids")
raise "Missing launched IDs" unless launches.uniq.sort == ids - preflight_ids
pause_records = %w[operator-pause.json operator-pause-20261017.json].to_h do |name|
  record = JSON.parse(File.read(File.join(root, name)))
  raise "Active observation interrupted" unless record.fetch("running_observation_interrupted") == false
  length = record.fetch("log_bytes_at_pause")
  raise "Pause log changed" unless Digest::SHA256.hexdigest(log.byteslice(0, length)) == record.fetch("log_sha256_at_pause")
  record.fetch("observation_sha256").each do |file, digest|
    raise "Paused report changed: #{file}" unless Digest::SHA256.file(File.join(root, "observations", file)).hexdigest == digest
  end
  [record.fetch("progress_before_pause").fetch("active_id"), { "receipt" => name, "sha256" => Digest::SHA256.file(File.join(root, name)).hexdigest }]
end
raise "Unexplained duplicate controller launch" unless launches.tally.select { |_, n| n > 1 } == pause_records.keys.to_h { |id| [id, 2] }
cleanup_retained = isolation.fetch("cleanup_fix").fetch("completed_observation_retained_without_rerun")
raise "Completed cleanup-recovery result changed" unless reports.fetch(cleanup_retained.fetch("id")) == cleanup_retained
provider_retries = launch_positions.each_with_index.filter_map do |(start, id), index|
  finish = launch_positions[index + 1]&.first || log.bytesize
  excerpt = log.byteslice(start, finish - start)
  failures = excerpt.scan(/API error after ([0-9.]+) seconds \(status ([0-9]+), ([^)]+)\)/)
  next if failures.empty?
  raise "Unrecognized retry history: #{id}" unless failures.size == 1 && failures.first[1..] == ["429", "api_error"] &&
    excerpt.include?("#{id} (attempt 2)") && !excerpt.include?("#{id} (attempt 3)") && excerpt.include?("Waiting 120s, then retrying")
  row = reports.fetch(id)
  raise "Accepted timing not bound to log: #{id}" unless excerpt.include?("Done in #{row.fetch('raw_total_seconds')} seconds.")
  { "id" => id, "provider_status" => 429, "failed_attempt_seconds" => failures.first.first.to_f,
    "explicit_retry_wait_seconds" => 120, "quota_wait_seconds" => excerpt.scan(/Usage(?: guard)? for fable .*?, waiting (\d+)s/).sum { |match| match.first.to_i },
    "accepted_attempt_seconds" => row.fetch("raw_total_seconds"), "accepted_total_tokens" => row.fetch("total_tokens"),
    "excerpt_start_byte" => start, "excerpt_bytes" => excerpt.bytesize, "excerpt_sha256" => Digest::SHA256.hexdigest(excerpt),
    "observation_sha256" => Digest::SHA256.file(File.join(root, "observations", "#{id}.json")).hexdigest }
end
raise "Unexpected provider retry count" unless provider_retries.size == 7
receipt_hashes = Dir[File.join(root, "provider-retry*.json")].sort.to_h do |path|
  receipt = JSON.parse(File.read(path))
  evidence = receipt.fetch("evidence")
  raise "Retry log prefix changed: #{path}" unless Digest::SHA256.hexdigest(log.byteslice(0, evidence.fetch("prefix_bytes"))) == evidence.fetch("prefix_sha256")
  if receipt.key?("accepted_attempt_seconds")
    row = reports.fetch(receipt.fetch("id"))
    raise "Retry acceptance differs: #{path}" unless receipt.fetch("accepted_attempt_seconds") == row.fetch("raw_total_seconds") && receipt.fetch("accepted_total_tokens") == row.fetch("total_tokens")
    retry_row = provider_retries.find { |candidate| candidate.fetch("id") == receipt.fetch("id") }
    raise "Retry wait differs: #{path}" unless retry_row && %w[failed_attempt_seconds explicit_retry_wait_seconds quota_wait_seconds].all? { |key| retry_row.fetch(key) == receipt.fetch(key) }
  end
  [File.basename(path), Digest::SHA256.file(path).hexdigest]
end
resume = JSON.parse(File.read(File.join(root, "quota-resume-20261106/prepared.json")))
resume.fetch("observation_sha256").each do |file, digest|
  raise "Pre-resume report changed: #{file}" unless Digest::SHA256.file(File.join(root, "observations", file)).hexdigest == digest
end
summary = { "schema_version" => 1, "checked_at" => Time.now.utc.iso8601, "campaign_id" => batch,
  "source_commit" => commit, "source_repository" => repository, "source_branch" => "claude", "pushed" => false,
  "observations" => reports.size, "outcomes" => reports.values.group_by { |row| row.fetch("outcome") }.transform_values(&:size),
  "tracked_files" => entries.size, "uncompressed_bytes" => entries.sum { |entry| entry.fetch("bytes") },
  "verified_metadata_sha256_fingerprints" => reports.values.sum { |row| row.fetch("sha256").size },
  "aggregate_accounting_fields_verified_per_observation" => 8, "native_cleanup_receipts" => 220,
  "controller_launches" => launches.size, "preflight_reused" => preflight_ids,
  "prelaunch_quota_pause_reentries" => pause_records, "accepted_generation_invocations" => 220,
  "provider_failed_attempts" => provider_retries, "provider_retry_receipt_sha256" => receipt_hashes,
  "provider_retry_timing" => "Failed attempts, outer backoff and quota waits are already outside each accepted attempt's fresh timer. No additional subtraction or regeneration is required. Failed-attempt token counters are unavailable in the retained native evidence.",
  "read_only_admission_recovery" => "QT CUDA r2 legacy task notification and Roomsim OpenMP r3 post-completion cleanup were admitted from their existing complete outputs; neither was regenerated.",
  "isolated_observations" => 125, "pre_isolation_observations_preserved" => preserved.size,
  "pre_resume_observations_preserved" => resume.fetch("observation_sha256").size,
  "retry_count" => reports.values.sum { |row| row.fetch("retry_count") },
  "retry_backoff_seconds" => reports.values.sum { |row| row.fetch("retry_backoff_seconds") },
  "generation_seconds" => reports.values.sum { |row| row.fetch("total_seconds") },
  "raw_generation_seconds" => reports.values.sum { |row| row.fetch("raw_total_seconds") },
  "mean_generation_minutes" => reports.values.sum { |row| row.fetch("total_seconds") } / reports.size / 60,
  "total_tokens" => reports.values.sum { |row| row.fetch("total_tokens") },
  "generation_log_bytes" => log.bytesize, "generation_log_sha256" => Digest::SHA256.hexdigest(log),
  "checks_passed" => ["Exact original IDs and metadata retained", "Fresh observation checker matches every saved report",
    "Independent aggregate parser matches without warnings", "Unique accepted session per observation", "Only this batch committed; worktree unchanged",
    "No gitlinks, symlinks, build directories or executable binaries retained", "All cleanup receipts verified; evaluation account empty",
    "Pauses and provider retries reconciled without repeating accepted observations"],
  "validation_started" => false, "benchmarking_started" => false,
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest }
raise "Progress totals differ" unless summary.fetch("total_tokens") == progress.fetch("retained_total_tokens") &&
  summary.fetch("raw_generation_seconds").round(2) == progress.fetch("raw_generation_seconds")
if previous_audit
  summary["operator_summary_correction"] = { "previous_audit_sha256" => previous_audit,
    "reason" => "Recognize the original Usage for fable log format as well as the later Usage guard for fable format; the first two wait totals now agree with their original receipts. Accepted program data and timings are unchanged." }
  FileUtils.cp(File.join(root, File.basename(__FILE__)), File.join(root, "audit-completion-before-legacy-quota-log.rb"))
  File.rename(target, File.join(root, "completion-audit-before-legacy-quota-log.json"))
end
File.open(target, File::WRONLY | File::CREAT | File::EXCL, 0o644) { |file| file.write(JSON.pretty_generate(summary) + "\n") }
FileUtils.cp(__FILE__, root)
puts JSON.pretty_generate(summary)
