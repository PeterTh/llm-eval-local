require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

root = "/home/petert/llm_para_campaigns/20261002-142720-opus55-medium"
runtime = "/tmp/opus55-generation.Lx4eWo"
source = "/home/petert/llm_eval/experiment"
commit = "5fd05f01581a0b483aed324b070601d18132cb5b"
revision = File.join(root, "supervision-revisions", commit)
raise "Cleanup revision already exists" if File.exist?(revision)
require File.join(source, "lib/generation_cleanup")
raise "llmtest is busy" unless GenerationCleanup.new.pids.empty?
state, status = Open3.capture2("systemctl", "--user", "show", "llm-opus55-generation-20261002-142720.service", "--value", "-p", "ActiveState")
raise "Generation service is not stopped" unless status.success? && %w[failed inactive].include?(state.strip)
head, status = Open3.capture2("git", "-C", source, "rev-parse", "HEAD")
raise "Unexpected source commit" unless status.success? && head.strip == commit
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
original = JSON.parse(File.read(File.join(root, "supervision.json")))
manifest.fetch("files").each do |path, digest|
  raise "Frozen generation script changed: #{path}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), path)).hexdigest == digest
end
original.fetch("files").each do |path, digest|
  raise "Unexpected old runtime supervisor: #{path}" unless Digest::SHA256.file(File.join(runtime, "supervisor", path)).hexdigest == digest
end
reports = Dir[File.join(root, "observations", "*.json")].map { |path| JSON.parse(File.read(path)) }
raise "Unexpected completed count" unless reports.size == 73
reports.each do |report|
  report.fetch("sha256").each do |name, digest|
    path = File.join(manifest.fetch("persistent_results"), report.fetch("id"), name)
    raise "Completed observation changed: #{path}" unless Digest::SHA256.file(path).hexdigest == digest
  end
end
files = original.fetch("files").keys + ["lib/generation_cleanup.rb"]
FileUtils.mkdir_p(revision)
%w[progress.json monitor-status.json].each { |name| FileUtils.cp(File.join(root, name), File.join(revision, "before-#{name}")) }
files.each do |path|
  persistent = File.join(revision, path)
  target = File.join(runtime, "supervisor", path)
  FileUtils.mkdir_p(File.dirname(persistent))
  FileUtils.cp(File.join(source, path), persistent)
  File.chmod(0444, persistent)
  next if File.file?(target) && Digest::SHA256.file(target).hexdigest == Digest::SHA256.file(persistent).hexdigest
  File.chmod(0644, target) if File.file?(target)
  FileUtils.cp(persistent, target)
  File.chmod(0444, target)
end
FileUtils.cp(File.join(runtime, "cleanup-live-test.json"), File.join(revision, "cleanup-live-test.json"))
FileUtils.cp(File.join(runtime, "test-cleanup.rb"), File.join(revision, "test-cleanup.rb"))
FileUtils.cp(__FILE__, File.join(revision, "deploy-cleanup.rb"))
FileUtils.cp(File.join(runtime, "FOLLOWUP.md"), File.join(root, "FOLLOWUP.md"))
journal, status = Open3.capture2("journalctl", "--user", "-u", manifest.fetch("generation_unit"),
  "--since", "2026-10-03 21:03:15", "--until", "2026-10-03 21:03:40", "--no-pager")
raise "Cannot retain stop journal" unless status.success?
File.write(File.join(revision, "stop-journal.txt"), journal)
record = { "deployed_at" => Time.now.utc.iso8601, "source_commit" => commit,
  "supersedes_source_commit" => original.fetch("source_commit"), "completed_observations_preserved" => reports.size,
  "generation_snapshot_unchanged" => true, "cleanup_wait_limit_seconds" => GenerationCleanup::WAIT_SECONDS,
  "next_id" => "roomsim_claude-opus-5.5-cc-medium_mpi_r2", "pending_count" => 147,
  "tests" => "55 tests, 322 assertions; all passed. A disposable llmtest sleep process was killed and absence verified in 0.696826 seconds.",
  "files" => files.to_h { |path| [path, Digest::SHA256.file(File.join(revision, path)).hexdigest] },
  "policy" => "Verified post-run cleanup only; no empty-account delay, no pre-launch killing, two-second poll bound, no generated-program execution or changes." }
File.write(File.join(revision, "amendment.json"), JSON.pretty_generate(record) + "\n")
puts JSON.pretty_generate(record)
