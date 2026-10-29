# frozen_string_literal: true

# Reuses the native Sol 6.1 completion checks and Haiku's retention/cleanup gates.
# Run only after generation, final usage recovery and the original-source commit.
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

root = "/home/petert/llm_para_campaigns/20261028-200951-terra61-codex-medium"
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
completion_path = File.join(root, "completion.json")
raise "Generation has not completed" unless File.file?(completion_path)
completion = JSON.parse(File.read(completion_path))
raise "Controller has not finalized" unless JSON.parse(File.read(File.join(root, "progress.json"))).fetch("status") == "complete"
require File.join(root, "method/lib/codex_generation_observation")
require File.join(root, "method/lib/generation_cleanup")
raise "Evaluation account is not idle" unless GenerationCleanup.new.pids.empty?
target = File.join(root, "completion-audit.json")
raise "Completion audit already exists" if File.exist?(target)

def git(repository, *arguments)
  output, error, status = Open3.capture3("git", "-C", repository, *arguments)
  raise "Git check failed: #{error}" unless status.success?
  output
end

ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true)
raise "Campaign selection differs" unless ids.size == 220 && ids.uniq == ids && manifest.fetch("expected_runs") == ids.size
expected_ids = manifest.fetch("benchmarks").product(manifest.fetch("models").keys,
  manifest.fetch("backends"), (1..manifest.fetch("repetitions")).to_a).map { |benchmark, model, backend, repetition|
    "#{benchmark}_#{model}_#{backend}_r#{repetition}"
  }
raise "Factorial campaign coverage differs" unless expected_ids.sort == ids.sort
batch = manifest.fetch("campaign_id")
results = manifest.fetch("persistent_results")
repository = File.dirname(results)
commit = completion.fetch("source_commit")
raise "Completion scope differs" unless completion.fetch("observations") == ids.size && Dir.children(results).sort == ids.sort
raise "Observation scope differs" unless Dir[File.join(root, "observations", "*.json")].map { |path| File.basename(path, ".json") }.sort == ids.sort
raise "Source commit differs" unless git(repository, "rev-parse", "HEAD").strip == commit
raise "Wrong source branch" unless git(repository, "branch", "--show-current").strip == manifest.fetch("source_branch")
raise "Batch worktree changed" unless git(repository, "status", "--porcelain", "--", batch).empty?
changed = git(repository, "diff-tree", "--no-commit-id", "--name-only", "-z", "-r", commit).split("\0")
raise "Commit includes unrelated paths" unless !changed.empty? && changed.all? { |path| path.start_with?(batch + "/") }
entries = git(repository, "ls-tree", "-r", "-l", "-z", commit, "--", batch).split("\0").map do |line|
  attributes, path = line.split("\t", 2)
  mode, type, oid, size = attributes.split
  raise "Nonregular retained artifact: #{path}" unless %w[100644 100755].include?(mode) && type == "blob"
  raise "Build or repository artifact retained: #{path}" if path.split("/").any? { |part|
    part.match?(/\A(?:build(?:[-_].*)?|cmake-build-.*|bin|CMakeFiles|node_modules|\.git(?:\.agent-backup)?|\.hg|\.svn)\z/i)
  }
  raise "Unexpected retained artifact extension: #{path}" unless %w[.txt .log .cpp .cu .h .hpp .inc .c .cc .cxx .cuh .hxx .inl .cmake].include?(File.extname(path))
  magic = File.binread(File.join(repository, path), 4)
  raise "Binary signature in retained output: #{path}" if magic.start_with?("\x7fELF".b, "MZ".b, "PK\x03\x04".b)
  { "path" => path, "bytes" => Integer(size), "git_blob" => oid }
end
tracked = entries.map { |entry| entry.fetch("path") }
raise "Committed program scope differs" unless tracked.map { |path| path.split("/")[1] }.uniq.sort == ids.sort
ignored = git(repository, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z", "--", batch).split("\0")
ignored_source = ignored.select { |path| path.match?(/\.(?:c|cc|cpp|cxx|cu|cuh|h|hpp|hxx|inl|inc|cmake)\z/i) }
raise "Potential source ignored: #{ignored_source.inspect}" unless ignored_source.empty?

profile = manifest.fetch("models").fetch("gpt-6.1-terra-medium")
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflights").fetch(0)
required = %w[output.txt timing.txt instruction.txt process-status.txt codex-filesystem.txt]
reports = ids.to_h do |id|
  report = CodexGenerationObservation.read(File.join(results, id), model: profile.fetch("model"),
    effort: profile.fetch("reasoning_effort"), version: manifest.fetch("codex_version"),
    timeout_seconds: manifest.fetch("per_run_timeout_seconds"), baseline: baseline)
  raise "Saved observation differs: #{id}" unless report == JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
  required.each { |name| raise "Required metadata not retained: #{id}/#{name}" unless tracked.include?("#{batch}/#{id}/#{name}") }
  isolation = report.fetch("filesystem_isolation")
  raise "Isolation policy changed: #{id}" unless isolation.fetch("policy") == manifest.fetch("generation_filesystem_policy")
  raise "Isolation implementation changed: #{id}" unless isolation.fetch("implementation_sha256") == manifest.fetch("files").fetch("lib/generation_filesystem.rb")
  manifest.fetch("codex_companions").each do |name, companion|
    raise "Companion changed: #{id}" unless isolation.fetch("harness_companions").fetch(name).fetch("sha256") == companion.fetch("sha256")
  end
  cleanup = JSON.parse(File.read(File.join(root, "cleanup", "#{id}.json")))
  raise "Cleanup failed: #{id}" unless cleanup.fetch("verified_empty")
  [id, report]
end
raise "Reused native session" unless reports.values.map { |row| row.fetch("session_id") }.uniq.size == ids.size
usage_path = File.join(root, "codex-usage.jsonl")
receipt = JSON.parse(File.read(File.join(root, "usage-recovery.json")))
raise "Usage receipt digest differs" unless Digest::SHA256.file(usage_path).hexdigest == receipt.fetch("sha256")
usage = CodexUsage.load_records(usage_path)
completed_ids = reports.keys.select { |id| reports.fetch(id).fetch("outcome") == "completed" }
unavailable = reports.values.reject { |row| row.fetch("outcome") == "completed" }.map { |row| row.slice("id", "outcome") }
raise "Usage coverage differs" unless usage.keys.sort == completed_ids.sort && receipt.fetch("records") == completed_ids.size &&
  receipt.fetch("unavailable").sort_by { |row| row.fetch("id") } == unavailable.sort_by { |row| row.fetch("id") }
usage.each do |id, record|
  raise "CLI drift: #{id}" unless record.fetch("cli_version") == manifest.fetch("codex_version")
  CodexUsage.verify_transcript!(record, id: id, batch: batch, path: File.join(results, id, "output.txt"))
  archived = reports.fetch(id).fetch("archived_sessions").find { |row| row.fetch("path") == record.fetch("session_path") }
  raise "Usage not bound to isolated archive: #{id}" unless archived && archived.fetch("sha256") == record.fetch("session_sha256")
end
total_tokens = usage.values.sum { |row| row.fetch("usage").fetch("total_tokens") }
raise "Usage total differs" unless total_tokens == receipt.fetch("total_tokens")
preflight = JSON.parse(File.read(File.join(root, "preflight-review.json")))
raise "Accepted pilot was not reused" unless preflight.fetch("passed") && preflight.fetch("reused_in_full_campaign") && !preflight.fetch("retained_pilot_reexecuted")
preflight.fetch("evidence_sha256").each do |name, digest|
  raise "Preflight evidence changed: #{name}" unless Digest::SHA256.file(File.join(root, name)).hexdigest == digest
end
launch_records = %w[preflight.log run.log].flat_map { |name|
  File.read(File.join(root, name)).lines.filter_map { |line|
    match = line.match(/^Launching ([a-zA-Z0-9_.-]+) at /)
    { "id" => match[1], "line" => line.chomp } if match
  }
}
recoveries = Dir[File.join(root, "failed-attempts", "*", "attempt-*", "recovery.json")].sort.map do |path|
  recovery = JSON.parse(File.read(path))
  archive = File.dirname(path)
  id = recovery.fetch("id")
  raise "Unexpected recovery scope" unless ids.include?(id) && recovery.fetch("valid_observations_repeated").zero? &&
    recovery.fetch("model_effort_prompt_budget_and_inputs_unchanged") && recovery.fetch("process_status").fetch("exit_status") == 1
  raise "Missing capacity evidence" unless !recovery.fetch("capacity_error_lines").empty? && recovery.fetch("capacity_error_lines").all? { |row|
    row.fetch("text").start_with?("ERROR: Selected model is at capacity.")
  }
  recovery.fetch("sha256").each do |relative, sha|
    raise "Failed-attempt archive changed" unless Digest::SHA256.file(File.join(archive, "output", relative)).hexdigest == sha
  end
  recovery.fetch("accepted_observation_sha256").each do |name, sha|
    raise "Earlier accepted observation changed" unless Digest::SHA256.file(File.join(root, "observations", name)).hexdigest == sha
  end
  raise "Failed launch not uniquely bound" unless launch_records.count { |row| row.fetch("line") == recovery.fetch("failed_launch_line") } == 1
  finished_path = File.join(archive, "retry-completed.json")
  finished = JSON.parse(File.read(finished_path))
  raise "Retry evidence differs" unless finished.fetch("retry_completed") && finished.fetch("id") == id &&
    finished.fetch("replacement_observation_sha256") == Digest::SHA256.file(File.join(root, "observations", "#{id}.json")).hexdigest
  { "id" => id, "recovery_path" => path.delete_prefix(root + "/"), "recovery_sha256" => Digest::SHA256.file(path).hexdigest,
    "retry_completion_sha256" => Digest::SHA256.file(finished_path).hexdigest,
    "failed_launch_line" => recovery.fetch("failed_launch_line"), "excluded_seconds" => recovery.fetch("excluded_failed_attempt_seconds") }
end
excluded_launches = recoveries.map { |row| row.fetch("failed_launch_line") }
raise "Duplicate excluded launch" unless excluded_launches.uniq == excluded_launches
launches = launch_records.reject { |row| excluded_launches.include?(row.fetch("line")) }.map { |row| row.fetch("id") }
raise "Accepted generation repeated or missing" unless launches == ids
setup_reviews = manifest.fetch("infrastructure_attempts").map do |path|
  { "path" => path, "sha256" => Digest::SHA256.file(File.join(root, path)).hexdigest }
end
beam = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium"
raise "Beam hold absent or inference started" unless File.file?(File.join(beam, "STOP")) && Dir[File.join(beam, "observations", "*.json")].empty?

summary = {
  "schema_version" => 1, "checked_at" => Time.now.utc.iso8601, "campaign_id" => batch,
  "source_commit" => commit, "source_repository" => repository, "source_branch" => manifest.fetch("source_branch"),
  "observations" => ids.size, "outcomes" => reports.values.group_by { |row| row.fetch("outcome") }.transform_values(&:size),
  "tracked_files" => entries.size, "uncompressed_bytes" => entries.sum { |entry| entry.fetch("bytes") },
  "required_metadata_files" => ids.size * required.size, "native_cleanup_receipts" => ids.size,
  "accepted_generation_invocations" => launches.size, "unaccepted_setup_attempts" => setup_reviews,
  "provider_capacity_recoveries" => recoveries,
  "excluded_provider_capacity_attempt_seconds" => recoveries.sum { |row| row.fetch("excluded_seconds") },
  "usage_records" => usage.size, "usage_complete" => unavailable.empty?, "usage_unavailable" => unavailable,
  "inclusive_total_tokens" => total_tokens, "usage_sha256" => receipt.fetch("sha256"),
  "generation_seconds" => reports.values.sum { |row| row.fetch("raw_total_seconds") }.round(6),
  "by_backend" => reports.values.group_by { |row| row.fetch("id").split("_")[-2] }.transform_values { |rows|
    seconds = rows.sum { |row| row.fetch("raw_total_seconds") }
    { "observations" => rows.size, "generation_seconds" => seconds.round(6), "mean_generation_seconds" => seconds / rows.size }
  },
  "checks_passed" => ["All original program IDs and required metadata retained in one batch-only commit",
    "Fresh observation verification matches retained reports; pinned isolation and companion evidence agrees",
    "Exact completed-session counters are bound to transcript and isolated archived-session hashes",
    "Unavailable timeout usage remains explicit, never fabricated as zero",
    "No repeated accepted generation; the corrected production pilot was reused once",
    "Initial setup failure remains separately retained and excluded from measured observations",
    "Any capacity-interrupted attempts are separately archived, exactly bound to the launch ledger and excluded; earlier accepted observations remain unchanged",
    "No gitlinks, symlinks, executable binaries or build trees retained; no ignored source extension detected",
    "Account cleanup verified; lower-priority Beam remains held"],
  "validation_started" => false, "benchmarking_started" => false, "pushed" => false,
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
  "next_stage" => "Verify upstream and push originals before native validation; inspect request-context pricing applicability only with generation finished."
}
FileUtils.cp(__FILE__, File.join(root, File.basename(__FILE__)))
temporary = "#{target}.#{Process.pid}.tmp"
File.write(temporary, JSON.pretty_generate(summary) + "\n")
File.rename(temporary, target)
puts JSON.pretty_generate(summary)
