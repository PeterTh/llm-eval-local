require "json"
require "digest"
require "open3"
require "time"

root = "/home/petert/llm_para_campaigns/20261006-204623-sol61-medium-xhigh"
require File.join(root, "method/lib/codex_usage")
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
completion = JSON.parse(File.read(File.join(root, "completion.json")))
receipt = JSON.parse(File.read(File.join(root, "usage-recovery.json")))
ids = File.readlines(File.join(root, "run-ids.txt"), chomp: true).sort
batch = manifest.fetch("campaign_id")
results = manifest.fetch("persistent_results")
repository = File.dirname(results)
usage_path = File.join(root, "codex-usage.jsonl")
raise "Usage receipt digest differs" unless Digest::SHA256.file(usage_path).hexdigest == receipt.fetch("sha256")
usage = CodexUsage.load_records(usage_path)
raise "Usage scope differs" unless usage.keys.sort == ids && receipt.fetch("records") == ids.size && receipt.fetch("unavailable").empty?
reports = ids.to_h { |id| [id, JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))] }
ids.each do |id|
  report = reports.fetch(id)
  raise "Incomplete observation: #{id}" unless report.fetch("outcome") == "completed"
  raise "CLI drift: #{id}" unless usage.fetch(id).fetch("cli_version") == manifest.fetch("codex_version")
  CodexUsage.verify_transcript!(usage.fetch(id), id: id, batch: batch, path: File.join(results, id, "output.txt"))
  report.fetch("sha256").each do |name, digest|
    raise "Metadata changed: #{id}/#{name}" unless Digest::SHA256.file(File.join(results, id, name)).hexdigest == digest
  end
end

def git(repository, *arguments)
  output, error, status = Open3.capture3("git", "-C", repository, *arguments)
  raise "Git check failed: #{error}" unless status.success?
  output
end

commit = completion.fetch("source_commit")
raise "Source commit differs" unless git(repository, "rev-parse", "HEAD").strip == commit
paths = git(repository, "diff-tree", "--no-commit-id", "--name-only", "-z", "-r", commit).split("\0")
raise "Commit contains unrelated paths" unless paths.all? { |p| p.start_with?(batch + "/") }
raise "Tracked outputs changed" unless git(repository, "diff", "HEAD", "--", batch).empty?
tree = git(repository, "ls-tree", "-r", "-l", "-z", commit, "--", batch).split("\0").map do |line|
  metadata, path = line.split("\t", 2)
  mode, type, object, bytes = metadata.split
  raise "Non-file entry: #{path}" unless type == "blob" && %w[100644 100755].include?(mode)
  head = File.binread(File.join(repository, path), 4)
  raise "Binary signature in retained output: #{path}" if head.start_with?("\x7fELF".b, "PK\x03\x04".b)
  { "path" => path, "bytes" => bytes.to_i }
end
raise "Commit/result scope differs" unless tree.map { |r| r.fetch("path").split("/")[1] }.uniq.sort == ids
raise "Build artifacts in commit" if tree.any? { |r| r.fetch("path").split("/").any? { |p| p.match?(/\A(?:build(?:[-_].*)?|bin|CMakeFiles|cmake-build-.*|\.git)\z/) } }
ignored = git(repository, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z", "--", batch).split("\0")
ignored_source = ignored.select { |p| p.match?(/\.(?:c|cc|cxx|cuh|hxx|inl|cmake)\z/i) }
raise "Potential program source ignored: #{ignored_source.inspect}" unless ignored_source.empty?
totals = usage.values.sum { |r| r.fetch("usage").fetch("total_tokens") }
raise "Token receipt total differs" unless totals == receipt.fetch("total_tokens")
by_profile = reports.group_by { |_id, report| report.fetch("reasoning_effort") }.transform_values do |rows|
  seconds = rows.sum { |_id, report| report.fetch("raw_total_seconds") }
  tokens = rows.sum { |id, _report| usage.fetch(id).fetch("usage").fetch("total_tokens") }
  { "observations" => rows.size, "generation_seconds" => seconds.round(2), "mean_generation_seconds" => (seconds / rows.size).round(2),
    "inclusive_total_tokens" => tokens, "mean_inclusive_total_tokens" => (tokens.to_f / rows.size).round(2) }
end
record = { "verified_at" => Time.now.utc.iso8601, "campaign_id" => batch, "observations" => ids.size,
  "source_commit" => commit, "committed_files" => tree.size, "committed_bytes" => tree.sum { |r| r.fetch("bytes") },
  "files_per_observation" => tree.group_by { |r| r.fetch("path").split("/")[1] }.values.group_by(&:size).transform_values(&:size),
  "usage_records" => usage.size, "inclusive_total_tokens" => totals, "usage_evidence" => "codex-usage.jsonl",
  "by_effort" => by_profile, "validation_started" => false, "benchmarking_started" => false,
  "archived_capacity_failures" => Dir[File.join(root, "failed-attempts", "*", "attempt-*", "recovery.json")].size,
  "scope_note" => "All original generation outcomes completed; scientific validation and performance evaluation remain separate stages." }
File.write(File.join(root, "post-generation-verification.json"), JSON.pretty_generate(record) + "\n")
puts JSON.pretty_generate(record)
