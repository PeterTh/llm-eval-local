# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "time"
require "fileutils"
$stdout.sync = true
$stderr.sync = true

campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
amendment = manifest.fetch("filesystem_amendment").fetch("path")
receipt = JSON.parse(File.read(File.join(amendment, "amendment.json")))
ids = receipt.fetch("affected_observations")
results = manifest.fetch("persistent_results")
source_repo = File.dirname(results)
raise "Wrong replacement scope" unless ids.size == 24 && ids.uniq == ids
raise "Frozen driver changed" unless Digest::SHA256.file(__FILE__).hexdigest == receipt.fetch("driver_sha256")
require File.join(manifest.fetch("working_directory"), "tools/generation_campaign")

def checked(*args)
  out, err, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{err}\n#{out}" unless status.success?
  out
end

def write_json(path, data)
  temp = "#{path}.#{Process.pid}.tmp"
  File.write(temp, JSON.pretty_generate(data) + "\n")
  File.rename(temp, path)
end

unchanged = JSON.parse(File.read(File.join(amendment, "unchanged-files.json")))
verify_unchanged = lambda do
  unchanged.each do |relative, sha|
    path = File.join(source_repo, relative)
    raise "Unrelated retained file changed: #{relative}" unless File.file?(path) && Digest::SHA256.file(path).hexdigest == sha
  end
  original = JSON.parse(File.read(File.join(amendment, "unchanged-observations.json")))
  original.each do |id, report|
    raise "Unrelated observation changed: #{id}" unless JSON.parse(File.read(File.join(campaign, "observations", "#{id}.json"))) == report
  end
end
checkpoint = lambda do |state, extra = {}|
  reports = ids.filter_map do |id|
    path = File.join(campaign, "observations", "#{id}.json")
    JSON.parse(File.read(path)) if File.file?(path)
  end
  write_json(File.join(amendment, "progress.json"), {
    "checked_at" => Time.now.utc.iso8601, "state" => state, "expected" => 24,
    "completed" => reports.size, "retained_unchanged" => 196,
    "total_seconds" => reports.sum { |r| r.fetch("total_seconds") },
    "outcomes" => reports.group_by { |r| r.fetch("outcome") }.transform_values(&:size)
  }.merge(extra))
end

lock = nil
host_lock = nil
begin
  raise "Already completed; do not repeat generation" if File.exist?(File.join(amendment, "completion.json"))
  lock = File.open(File.join(campaign, "controller.lock"), "a")
  raise "Another controller is active" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
  host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
  raise "Another native evaluation phase owns the host" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
  verify_unchanged.call
  manifest.fetch("files").each do |relative, sha|
    raise "Frozen method changed: #{relative}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), relative)).hexdigest == sha
  end
  driver = GenerationCampaign.new(campaign, stop_files: [File.join(amendment, "STOP")])
  baselines = JSON.parse(File.read(File.join(campaign, "preflight-gate.json"))).fetch("preflights")
  baseline = baselines.first
  ids.each do |id|
    checkpoint.call("running", "active_id" => id)
    driver.execute_observation(id, baseline: baseline, phase: "isolated_replacements")
    result = driver.observation(id, baseline: baseline)
    raise "Replacement lacks filesystem isolation" unless result.dig("filesystem_isolation", "policy") == "observation-mount-allowlist-v1"
    verify_unchanged.call
    checkpoint.call("running")
  end
  driver.ensure_account_idle!
  verify_unchanged.call
  checkpoint.call("retaining_replacements")
  branch = checked("git", "-C", source_repo, "branch", "--show-current").strip
  raise "Wrong generated-source branch" unless branch == manifest.fetch("source_branch")
  raise "Unrelated staged work exists" unless checked("git", "-C", source_repo, "diff", "--cached", "--name-only").empty?
  raise "Unexpected original-source HEAD" unless checked("git", "-C", source_repo, "rev-parse", "HEAD").strip == receipt.fetch("timing_corrected_source_commit")
  ids.each do |id|
    raise "Nested generated repository requires review: #{id}" unless Dir.glob(File.join(results, id, "**/.git"), File::FNM_DOTMATCH).empty?
  end
  batch = manifest.fetch("campaign_id")
  checked("git", "-C", source_repo, "add", "--", batch)
  changed = checked("git", "-C", source_repo, "diff", "--cached", "--name-only", "-z").split("\0")
  raise "Staged paths outside the 24 replacements" unless !changed.empty? && changed.all? { |p| p.split("/")[0] == batch && ids.include?(p.split("/")[1]) }
  entries = checked("git", "-C", source_repo, "ls-files", "--stage", "--", batch).lines
  raise "Non-regular generated-source entry" unless entries.all? { |line| line.start_with?("100644 ", "100755 ") }
  tracked = checked("git", "-C", source_repo, "ls-files", "-z", "--", batch).split("\0")
  ids.each do |id|
    required = %w[output.txt timing.txt instruction.txt process-status.txt] + OpenCodeHarness::EVIDENCE_FILES
    if OpenCodeGenerationTermination.read(File.join(results, id))
      required.delete("opencode-process.txt")
      required << OpenCodeGenerationTermination::FILENAME
    end
    required.each { |name| raise "Required replacement metadata ignored: #{id}/#{name}" unless tracked.include?("#{batch}/#{id}/#{name}") }
  end
  changed.each do |relative|
    path = File.join(source_repo, relative)
    next unless File.file?(path)
    raise "Build artifact staged: #{relative}" if relative.match?(%r{/(?:build[^/]*|CMakeFiles|node_modules|\.git)/}) || File.binread(path, 4) == "\x7fELF"
  end
  checked("git", "-C", source_repo, "commit", "--quiet", "-m", "Replace 24 DeepSeek observations after filesystem-isolation repair")
  source_commit = checked("git", "-C", source_repo, "rev-parse", "HEAD").strip
  completion = { "completed_at" => Time.now.utc.iso8601, "campaign_id" => batch,
    "observations" => 220, "replaced_observations" => 24, "retained_unchanged" => 196,
    "source_commit" => source_commit, "amendment" => amendment,
    "next_stage" => "Commit/push retention, scoped validation, timing review/correction, unchanged-size benchmarking, then normal release. No special website marking; preserve paper evidence." }
  write_json(File.join(amendment, "completion.json"), completion)
  write_json(File.join(campaign, "completion.json"), completion)
  driver.snapshot("complete")
  checkpoint.call("generation_complete", "source_commit" => source_commit)
  puts JSON.generate(completion)
rescue Exception => error
  checkpoint.call("needs_review", "error" => "#{error.class}: #{error.message}")
  warn "Replacement campaign stopped without rerunning retained observations: #{error.class}: #{error.message}"
  raise
ensure
  host_lock&.close
  lock&.close
end
