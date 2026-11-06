# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"
root = "/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra"
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
require File.join(manifest.fetch("working_directory"), "lib/codex_generation_observation")
require File.join(manifest.fetch("working_directory"), "lib/generation_cleanup")
raise "Generation not finalized" unless JSON.parse(File.read(File.join(root, "progress.json"))).fetch("status") == "complete"
raise "Account busy" unless GenerationCleanup.new.pids.empty?
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
completion = JSON.parse(File.read(File.join(root, "completion.json")))
target = File.join(root, "completion-audit.json")
raise "Already audited" if File.exist?(target)
def git(repo, *args)
  out, err, result = Open3.capture3("git", "-C", repo, *args)
  raise "Git failed: #{err}" unless result.success?
  out
end
def hashes(root)
  paths = Dir[File.join(root, "**", "*"), File.join(root, "**", ".*")].uniq.sort
  raise "Linked data" if paths.any? { |p| File.symlink?(p) }
  paths.select { |p| File.file?(p) }.to_h { |p| [p.delete_prefix(root + "/"), Digest::SHA256.file(p).hexdigest] }
end
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true)
expected = manifest.fetch("benchmarks").product(manifest.fetch("models").keys, manifest.fetch("backends"), (1..5).to_a).map { |b, m, p, r| "#{b}_#{m}_#{p}_r#{r}" }
raise "Coverage differs" unless ids.size == 220 && ids.uniq == ids && ids.sort == expected.sort && completion.fetch("observations") == 220
results = manifest.fetch("persistent_results")
repo = File.dirname(results)
batch = manifest.fetch("campaign_id")
commit = completion.fetch("source_commit")
raise "Output directories differ" unless Dir.children(results).sort == ids.sort
raise "Source HEAD differs" unless git(repo, "rev-parse", "HEAD").strip == commit && git(repo, "branch", "--show-current").strip == manifest.fetch("source_branch")
raise "Output worktree changed" unless git(repo, "status", "--porcelain", "--", batch).empty?
changed = git(repo, "diff-tree", "--no-commit-id", "--name-only", "-z", "-r", commit).split("\0")
raise "Unrelated paths committed" unless !changed.empty? && changed.all? { |path| path.start_with?(batch + "/") }
entries = git(repo, "ls-tree", "-r", "-l", "-z", commit, "--", batch).split("\0").map do |line|
  attributes, path = line.split("\t", 2)
  mode, type, oid, bytes = attributes.split
  raise "Nonregular artifact" unless %w[100644 100755].include?(mode) && type == "blob"
  raise "Build or nested repository retained" if path.split("/").any? { |part| part.match?(/\A(?:build(?:[-_].*)?|cmake-build-.*|bin|CMakeFiles|node_modules|\.git(?:\.agent-backup)?|\.hg|\.svn)\z/i) }
  raise "Unexpected extension: #{path}" unless %w[.txt .log .cpp .cu .h .hpp .inc .c .cc .cxx .cuh .hxx .inl .cmake].include?(File.extname(path))
  magic = File.binread(File.join(repo, path), 4)
  raise "Binary retained" if magic.start_with?("\x7fELF".b, "MZ".b, "PK\x03\x04".b)
  { "path" => path, "bytes" => Integer(bytes), "git_blob" => oid }
end
tracked = entries.map { |entry| entry.fetch("path") }
raise "Tracked scope differs" unless tracked.map { |path| path.split("/")[1] }.uniq.sort == ids.sort
ignored = git(repo, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z", "--", batch).split("\0")
raise "Potential source ignored" if ignored.any? { |path| path.match?(/\.(?:c|cc|cpp|cxx|cu|cuh|h|hpp|hxx|inl|inc|cmake)\z/i) }
first_revision = manifest.fetch("method_revisions").first
profile = manifest.fetch("models").fetch("gpt-6.1-terra-ultra")
reports = ids.to_h do |id|
  report = CodexGenerationObservation.read(File.join(results, id), model: profile.fetch("model"), effort: profile.fetch("reasoning_effort"),
    version: manifest.fetch("codex_version"), timeout_seconds: manifest.fetch("per_run_timeout_seconds"))
  raise "Saved report differs" unless report == JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  %w[output.txt timing.txt instruction.txt process-status.txt codex-filesystem.txt].each { |name| raise "Metadata not tracked" unless tracked.include?("#{batch}/#{id}/#{name}") }
  isolation = report.fetch("filesystem_isolation")
  expected_sha = if first_revision.fetch("retained_ids").include?(id)
    Digest::SHA256.file(File.join(first_revision.fetch("method_root"), "lib/generation_filesystem.rb")).hexdigest
  else
    raise "Missing pinned catalog" unless report.dig("model_catalog", "sha256") == manifest.dig("codex_model_catalog", "sha256")
    manifest.fetch("files").fetch("lib/generation_filesystem.rb")
  end
  raise "Isolation implementation differs" unless isolation.fetch("implementation_sha256") == expected_sha
  manifest.fetch("codex_companions").each { |name, item| raise "Companion differs" unless isolation.fetch("harness_companions").fetch(name).fetch("sha256") == item.fetch("sha256") }
  raise "Cleanup failed" unless JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json"))).fetch("verified_empty")
  [id, report]
end
usage_path = File.join(root, "codex-usage.jsonl")
usage_receipt = JSON.parse(File.read(File.join(root, "usage-recovery.json")))
raise "Usage digest differs" unless Digest::SHA256.file(usage_path).hexdigest == usage_receipt.fetch("sha256")
usage = CodexUsage.load_records(usage_path)
raise "Usage scope differs" unless usage.keys.sort == ids.sort && usage_receipt.fetch("records") == 220 && usage_receipt.fetch("unavailable").empty?
sessions = []
usage.each do |id, record|
  raise "Wrong accounting scope" unless record.fetch("schema_version") == 2 && record.fetch("source") == "codex_rollout_unique_thread_requests"
  CodexUsage.verify_transcript!(record, id: id, batch: batch, path: File.join(results, id, "output.txt"))
  archived = record.fetch("sessions").map { |s| { "path" => s.fetch("session_path"), "sha256" => s.fetch("session_sha256"), "bytes" => s.fetch("session_bytes") } }
  raise "Tree differs from archive" unless archived == reports.fetch(id).fetch("archived_sessions")
  sessions.concat(record.fetch("sessions").map { |s| s.fetch("session_id") })
end
raise "Session reused" unless sessions.uniq == sessions
totals = CodexTreeUsage.sum(usage.values.map { |r| r.fetch("usage") })
raise "Total differs" unless totals.fetch("total_tokens") == usage_receipt.fetch("total_tokens")
uncertain = usage.values.select { |r| r.fetch("interrupted_request_usage_uncertain") }.map { |r| r.fetch("run_id") }
raise "Uncertainty lost" unless uncertain == usage_receipt.fetch("interrupted_request_usage_uncertain")
preparation = JSON.parse(File.read(File.join(manifest.fetch("full_campaign_evidence_root"), "preparation.json")))
preparation.fetch("retained_pilot_files").each { |id, expected_hashes| raise "Pilot changed" unless hashes(File.join(results, id)) == expected_hashes }
repair = JSON.parse(File.read(File.join(manifest.fetch("catalog_repair_root"), "repair.json")))
raise "Superseded attempt changed" unless hashes(repair.fetch("original_attempt")) == repair.fetch("original_files")
logs = [File.join(root, "pilot.log"), File.join(manifest.fetch("catalog_repair_root"), "retry.log"), File.join(manifest.fetch("full_campaign_evidence_root"), "generation.log")]
launches = logs.flat_map { |path| File.readlines(path).filter_map { |line| line[/^Launching (\S+) at /, 1] } }
counts = launches.tally
raise "Launch history differs" unless counts.keys.sort == ids.sort && counts.all? { |id, n| n == (id == manifest.fetch("catalog_retry_id") ? 2 : 1) }
summary = { "schema_version" => 1, "checked_at" => Time.now.utc.iso8601, "campaign_id" => batch,
  "source_commit" => commit, "source_repository" => repo, "source_branch" => manifest.fetch("source_branch"),
  "observations" => 220, "tracked_files" => entries.size, "uncompressed_bytes" => entries.sum { |r| r.fetch("bytes") },
  "outcomes" => reports.values.group_by { |r| r.fetch("outcome") }.transform_values(&:size),
  "recorded_usage" => totals, "usage_records" => usage.size, "sessions" => sessions.size,
  "request_records" => usage.values.sum { |r| r.fetch("request_count") }, "usage_sha256" => usage_receipt.fetch("sha256"),
  "interrupted_request_usage_uncertain_count" => uncertain.size,
  "accepted_generation_invocations" => 220, "excluded_catalog_fallback_attempts" => 1,
  "pilot_reused_unchanged" => true, "cleanup_verified" => true, "archive_tree_accounting_verified" => true,
  "generation_seconds" => reports.values.sum { |r| r.fetch("raw_total_seconds") },
  "validation_started" => false, "benchmarking_started" => false, "pushed" => false,
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest }
File.write(target, JSON.pretty_generate(summary) + "\n")
FileUtils.cp(__FILE__, root)
puts JSON.pretty_generate(summary)
