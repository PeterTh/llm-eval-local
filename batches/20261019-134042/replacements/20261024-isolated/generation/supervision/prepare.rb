# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "tmpdir"
require "open3"
require "time"
$stdout.sync = true

REPO = "/home/petert/llm_eval/experiment"
METHOD = "fef761acc12f372908b7fd557b382beaed6028af"
SOURCE = "/home/petert/llm_para_experiments"
CAMPAIGN = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
AUDIT = File.join(CAMPAIGN, "evaluation/contamination-audit-20261023")
AMENDMENT = File.join(CAMPAIGN, "amendments/20261023-filesystem-isolation")
DRIVER = "/tmp/deepseek-isolated-replacements-driver-20261023.rb"
BATCH = "20261019-134042"
RESULTS = File.join(SOURCE, BATCH)

controller_lock = File.open(File.join(CAMPAIGN, "controller.lock"), "a")
raise "Another campaign controller is active" unless controller_lock.flock(File::LOCK_EX | File::LOCK_NB)
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Another native evaluation phase owns the host" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)

def checked(*args)
  out, err, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{err}\n#{out}" unless status.success?
  out
end

def hashes(root)
  Dir[File.join(root, "**", "*"), File.join(root, "**", ".*")].uniq.sort.filter_map do |path|
    next unless File.file?(path)
    raise "Unexpected symlink" if File.symlink?(path)
    [path.delete_prefix(root + "/"), Digest::SHA256.file(path).hexdigest]
  end.to_h
end

def write(path, data)
  File.write(path, JSON.pretty_generate(data) + "\n")
end

raise "Already prepared; inspect rather than overwrite" if File.exist?(AMENDMENT)
raise "Method HEAD differs" unless checked("git", "-C", REPO, "rev-parse", "HEAD").strip == METHOD
raise "Method staging not clean" unless checked("git", "-C", REPO, "diff", "--cached", "--name-only").empty?
raise "Generated-source staging not clean" unless checked("git", "-C", SOURCE, "diff", "--cached", "--name-only").empty?
raise "DeepSeek tracked outputs changed" unless checked("git", "-C", SOURCE, "status", "--porcelain", "--untracked-files=no", "--", BATCH).empty?
review = JSON.parse(File.read(File.join(AUDIT, "review.json")))
old = JSON.parse(File.read(File.join(CAMPAIGN, "campaign.json")))
raise "Generated-source HEAD differs" unless checked("git", "-C", SOURCE, "rev-parse", "HEAD").strip == review.fetch("timing_corrected_source_commit")
approved = review.fetch("definite_rerun_ids") + review.fetch("evaluator_only_ids")
all_ids = File.readlines(File.join(CAMPAIGN, "run-ids.txt"), chomp: true)
ids = all_ids.select { |id| approved.include?(id) }
raise "Replacement scope differs" unless ids.size == 24 && ids.uniq == ids && (approved - ids).empty?
raise "A production preflight is affected" unless (old.fetch("preflight_ids") & ids).empty?
require File.join(REPO, "lib/opencode_generation_observation")
reports = all_ids.to_h do |id|
  prior = JSON.parse(File.read(File.join(CAMPAIGN, "observations", "#{id}.json")))
  current = OpenCodeGenerationObservation.read(File.join(RESULTS, id), model: "opencode-go/deepseek-v4.1-flash", effort: "high")
  raise "Original observation changed: #{id}" unless prior == current
  [id, prior]
end
raise "Missing original outcomes" unless reports.size == 220 && reports.values.count { |r| r["outcome"] == "generation_model_terminated" } == 3
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
%w[llm-opencode-go-advertised-limits-20261021-092757.service llm-deepseek41-oc-benchmark-20261023.service llm-fable51-reset-handoff-20261023.timer llm-fable51-reset-handoff-20261023.service].each do |unit|
  state = checked("systemctl", "--user", "show", unit, "--property=ActiveState", "--value").strip
  raise "Conflicting unit active: #{unit}" if %w[active activating reloading].include?(state)
end
raise "Fable pause missing" unless File.exist?(File.join(old.fetch("paused_campaign").fetch("path"), "STOP"))
raise "MiniMax hold missing" unless File.exist?("/home/petert/llm_para_campaigns/20261019-134120-minimax31-flash-opencode-medium/STOP")
old.fetch("files").each do |relative, sha|
  raise "Original runtime changed" unless Digest::SHA256.file(File.join(old.fetch("working_directory"), relative)).hexdigest == sha
end
preflight = JSON.parse(File.readlines(File.join(AUDIT, "generation-isolation-preflight-20261023.log")).last)
raise "Isolation preflight differs" unless preflight.fetch("inferences_launched").zero? && preflight.dig("filesystem_isolation", "implementation_sha256") == Digest::SHA256.file(File.join(REPO, "lib/generation_filesystem.rb")).hexdigest
raise "Hardware probe missing" unless preflight.fetch("cuda_probe") == "cuda=7" && preflight.fetch("hybrid_probe").include?("ranks=2 threads=2")
tracked = checked("git", "-C", SOURCE, "ls-files", "-z", "--", BATCH).split("\0")
tracked_hashes = tracked.to_h do |relative|
  path = File.join(SOURCE, relative)
  raise "Non-regular tracked output: #{relative}" unless File.file?(path) && !File.symlink?(path)
  [relative, Digest::SHA256.file(path).hexdigest]
end
unchanged_hashes = tracked_hashes.reject { |relative, _| ids.include?(relative.split("/")[1]) }
old_hashes = tracked_hashes.select { |relative, _| ids.include?(relative.split("/")[1]) }
raise "Unchanged source count differs" unless unchanged_hashes.keys.map { |p| p.split("/")[1] }.uniq.size == 196

runtime = Dir.mktmpdir("deepseek-isolated-replacements-20261023-", "/tmp")
FileUtils.chmod(0755, runtime)
backup = Dir.mktmpdir("deepseek-contamination-superseded-20261023-", "/tmp")
FileUtils.mkdir_p(AMENDMENT, mode: 0700)
FileUtils.mkdir_p(File.join(AMENDMENT, "before"))
Dir[File.join(CAMPAIGN, "*.json")].each { |path| FileUtils.cp(path, File.join(AMENDMENT, "before", File.basename(path))) }
FileUtils.cp(__FILE__, File.join(AMENDMENT, "prepare.rb"))
FileUtils.cp(DRIVER, File.join(AMENDMENT, "run-replacements.rb"))
FileUtils.mkdir_p(File.join(runtime, "experiment"))
statuses = Open3.pipeline(["git", "-C", REPO, "archive", METHOD], ["tar", "-xf", "-", "-C", File.join(runtime, "experiment")])
raise "Method snapshot failed" unless statuses.all?(&:success?)
FileUtils.cp_r(File.join(old.fetch("runtime_root"), "benchmarks"), File.join(runtime, "benchmarks"))
raise "Sequential input changed" unless hashes(File.join(runtime, "benchmarks")) == old.fetch("benchmark_files")
FileUtils.cp(old.fetch("opencode_binary"), File.join(runtime, "opencode"), preserve: true)
raise "Binary changed" unless Digest::SHA256.file(File.join(runtime, "opencode")).hexdigest == OpenCodeHarness::BINARY_SHA256
FileUtils.cp(File.join(runtime, "experiment/tools/run_opencode_campaign.rb"), File.join(runtime, "run.rb"))
FileUtils.cp(DRIVER, File.join(runtime, "run-replacements.rb"))
File.write(File.join(runtime, "campaign.path"), CAMPAIGN + "\n")
File.write(File.join(AMENDMENT, "run-ids.txt"), ids.join("\n") + "\n")
write(File.join(AMENDMENT, "unchanged-files.json"), unchanged_hashes)
write(File.join(AMENDMENT, "superseded-files.json"), old_hashes)
write(File.join(AMENDMENT, "unchanged-observations.json"), reports.reject { |id, _| ids.include?(id) })
unit = "llm-deepseek41-isolated-replacements-20261023.service"
receipt = { "schema_version" => 1, "prepared_at" => Time.now.utc.iso8601,
  "authorization" => "User approved all 24 identified exposures, then the standard scoped validation/review/benchmark/release workflow. No special website marking; preserve evidence for the follow-up paper.",
  "affected_observations" => ids, "preserved_observations" => 196,
  "audit_review_sha256" => Digest::SHA256.file(File.join(AUDIT, "review.json")).hexdigest,
  "original_generated_source_commit" => review.fetch("original_generated_source_commit"),
  "timing_corrected_source_commit" => review.fetch("timing_corrected_source_commit"),
  "method_commit" => METHOD, "runtime_root" => runtime, "recoverable_worktree_backup" => backup,
  "source_preservation" => "Original generated and timing-corrected code/transcripts remain in existing Git commits; native scientific results remain untouched. Recoverable untracked build workspace moved to private local scratch, not duplicated in Git.",
  "replacement_selection" => "Exactly one new independent observation for each affected ID, regardless of correctness or performance; no best-of selection; preserve ordinary model failures.",
  "filesystem_policy" => GenerationFilesystem::POLICY, "driver_sha256" => Digest::SHA256.file(DRIVER).hexdigest,
  "previous_runtime_amendment" => old.fetch("runtime_amendment"), "generation_unit" => unit,
  "ordinary_failure_ids_retained" => reports.values.select { |r| r["outcome"] == "generation_model_terminated" }.map { |r| r["id"] },
  "remaining_transcript_audit" => "Deferred until DeepSeek is published, as requested.",
  "website" => "Normal replacement results only; no special contamination marking." }
write(File.join(AMENDMENT, "amendment.json"), receipt)
revised = old.merge("runtime_root" => runtime, "working_directory" => File.join(runtime, "experiment"),
  "opencode_binary" => File.join(runtime, "opencode"), "files" => hashes(File.join(runtime, "experiment")),
  "runtime_source_commit" => METHOD, "generation_filesystem_policy" => GenerationFilesystem::POLICY,
  "generation_unit" => unit, "filesystem_amendment" => { "path" => AMENDMENT, "affected_observations" => ids },
  "next_stages" => ["Retain the 24 isolated replacements; preserve 196 other observations", "Scoped validation", "Usual Luna timing review and uncertainty-only Sol adjudication", "Single timing-only correction commit and scoped revalidation", "Established-size affected-only benchmarking", "Normal winner review, pricing, package and website integration; no special website marking", "After DeepSeek publication, audit other campaigns separately"])
FileUtils.mkdir_p(File.join(AMENDMENT, "superseded-observations"))
ids.each do |id|
  source, target = File.join(RESULTS, id), File.join(backup, id)
  FileUtils.mv(source, target)
  old_hashes.select { |relative, _| relative.split("/")[1] == id }.each do |relative, sha|
    moved = File.join(backup, relative.delete_prefix(BATCH + "/"))
    raise "Superseded file changed in preservation" unless Digest::SHA256.file(moved).hexdigest == sha
  end
  FileUtils.mv(File.join(CAMPAIGN, "observations", "#{id}.json"), File.join(AMENDMENT, "superseded-observations", "#{id}.json"))
end
write(File.join(CAMPAIGN, "campaign.json"), revised)
raise "Wrong retained scope" unless Dir.children(RESULTS).sort == (all_ids - ids).sort && Dir[File.join(CAMPAIGN, "observations/*.json")].size == 196
dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=#{BATCH}", "--run-ids=#{AMENDMENT}/run-ids.txt")
File.write(File.join(AMENDMENT, "dry-run.log"), dry)
raise "Dry-run selection differs" unless dry.include?("Total number of experiments to run: 24") && ids.all? { |id| dry.include?(id) }
write(File.join(AMENDMENT, "progress.json"), { "state" => "prepared", "expected" => 24, "completed" => 0, "retained_unchanged" => 196 })
puts JSON.pretty_generate(receipt.reject { |key, _| key == "previous_runtime_amendment" })
puts "Prepared; no inference launched."
