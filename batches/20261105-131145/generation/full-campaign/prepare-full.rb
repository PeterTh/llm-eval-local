# frozen_string_literal: true
require "json"
require "fileutils"
require "tmpdir"
require "open3"
require "digest"
require "time"

def checked(*command)
  output, error, status = Open3.capture3(*command)
  raise "#{command.first} failed: #{error}\n#{output}" unless status.success?
  output
end

def hashes(root)
  paths = Dir[File.join(root, "**", "*"), File.join(root, "**", ".*")].uniq.sort
  raise "Linked data need review" if paths.any? { |path| File.symlink?(path) }
  paths.select { |path| File.file?(path) }.to_h { |path| [path.delete_prefix(root + "/"), Digest::SHA256.file(path).hexdigest] }
end

campaign = "/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra"
evidence = File.join(campaign, "full-campaign-20261105")
repo = "/home/petert/llm_eval/experiment"
commit = "0304617d39ccd7e2b1432f5ef7345e12997b43ac"
raise "Already prepared" if File.exist?(evidence)
manifest_path = File.join(campaign, "campaign.json")
original = JSON.parse(File.read(manifest_path))
raise "Wrong campaign" unless original.fetch("campaign_id") == "20261105-131145" && original.fetch("expected_runs") == 220
raise "Stopped" if File.exist?(File.join(campaign, "STOP"))
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
controller_lock = File.open(File.join(campaign, "controller.lock"), "a")
raise "Controller busy" unless controller_lock.flock(File::LOCK_EX | File::LOCK_NB)
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Account busy" unless status.exitstatus == 1 && pids.empty?
raise "Source HEAD differs" unless checked("git", "-C", repo, "rev-parse", "HEAD").strip == commit
raise "Staged source changes" unless checked("git", "-C", repo, "diff", "--cached", "--name-only").empty?
raise "Unexpected source worktree changes" unless checked("git", "-C", repo, "status", "--porcelain").lines.map(&:strip) == ["M experiment.rb"]
raise "Generated source index has staged work" unless checked("git", "-C", File.dirname(original.fetch("persistent_results")), "diff", "--cached", "--name-only").empty?
raise "Pilot review missing" unless JSON.parse(File.read(File.join(campaign, "preflight-review.json"))).fetch("passed")
raise "Pilot accounting check failed" unless JSON.parse(File.read(File.join(__dir__, "accounting-pilot-check.json"))).fetch("passed")
tests = JSON.parse(File.read(File.join(__dir__, "regression-tests.json")))
raise "Tests failed or skipped" unless tests.fetch("exit_status").zero? && tests.fetch("summary").include?("509 runs, 2967 assertions, 0 failures, 0 errors, 0 skips")
ids = File.readlines(File.join(campaign, "run-ids.txt"), chomp: true)
raise "Selection differs" unless ids.size == 220 && ids.uniq == ids
raise "Pilot result scope differs" unless Dir.children(original.fetch("persistent_results")).sort == original.fetch("preflight_ids").sort
retained = original.fetch("preflight_ids").to_h { |id| [id, hashes(File.join(original.fetch("persistent_results"), id))] }
runtime = Dir.mktmpdir("terra61-ultra-full-", "/tmp")
File.chmod(0755, runtime)
FileUtils.mkdir_p(File.join(runtime, "experiment"))
statuses = Open3.pipeline(["git", "-C", repo, "archive", commit], ["tar", "-xf", "-", "-C", File.join(runtime, "experiment")])
raise "Method archive failed" unless statuses.all?(&:success?)
FileUtils.cp_r(File.join(campaign, "sequential-input"), File.join(runtime, "benchmarks"))
raise "Sequential input changed" unless hashes(File.join(runtime, "benchmarks")) == original.fetch("benchmark_files")
FileUtils.cp(File.join(original.fetch("runtime_root"), "run.rb"), runtime)
FileUtils.cp(File.join(__dir__, "full-controller.rb"), runtime)
catalog = original.fetch("codex_model_catalog")
FileUtils.cp(catalog.fetch("path"), File.join(runtime, "model-catalog.json"))
FileUtils.cp(catalog.fetch("path") + ".receipt.json", File.join(runtime, "model-catalog.json.receipt.json"))
raise "Catalog changed" unless Digest::SHA256.file(File.join(runtime, "model-catalog.json")).hexdigest == catalog.fetch("sha256")
raise "Catalog receipt changed" unless Digest::SHA256.file(File.join(runtime, "model-catalog.json.receipt.json")).hexdigest == catalog.fetch("receipt_sha256")
FileUtils.mkdir_p(evidence)
FileUtils.cp(manifest_path, File.join(evidence, "campaign.before-full.json"))
FileUtils.cp(File.join(campaign, "progress.json"), File.join(evidence, "progress.before-full.json"))
FileUtils.cp_r(File.join(runtime, "experiment"), File.join(evidence, "method"))
%w[check-accounting.rb run-tests.rb regression-tests.json regression-tests.log accounting-pilot-check.json prepare-full.rb full-controller.rb launch-full.rb].each do |name|
  FileUtils.cp(File.join(__dir__, name), evidence)
end
File.write(File.join(runtime, "campaign.path"), campaign + "\n")
File.write(File.join(evidence, "campaign.path"), campaign + "\n")
manifest = original.merge("phase" => "production_generation", "full_campaign_authorized" => true, "yield_at" => nil,
  "full_campaign_evidence_root" => evidence, "source_commit" => commit, "files" => hashes(File.join(runtime, "experiment")),
  "runtime_root" => runtime, "working_directory" => File.join(runtime, "experiment"),
  "codex_model_catalog" => catalog.merge("path" => File.join(runtime, "model-catalog.json")),
  "codex_effective_context_window" => 475000,
  "orchestration_files" => %w[run.rb full-controller.rb].to_h { |name| [name, Digest::SHA256.file(File.join(runtime, name)).hexdigest] },
  "reuse" => "Reuse all four accepted full-budget observations; generate only the remaining 216.",
  "monitoring" => "Check initial progress, then at most four hours apart; closer near completion or anomalies. Session recovery only while idle. Timers do not notify the assistant.",
  "accounting" => "Schema-2 unique recorded requests across root and descendants; reconcile cumulative counters, preserve interrupted-request uncertainty.",
  "priority" => "Finish the full Terra experiment, including standard evaluation and publication, before resuming Fable. No Friday reset cutoff; no automatic banked quota-reset redemption.")
manifest.fetch("method_revisions") << { "commit" => commit, "method_root" => File.join(evidence, "method"),
  "scope" => "Remaining 216 observations and tree accounting; unchanged prompts, native delegation, model catalog and task budget" }
File.write(manifest_path + ".tmp", JSON.pretty_generate(manifest) + "\n")
File.rename(manifest_path + ".tmp", manifest_path)
require File.join(runtime, "experiment/tools/generation_campaign")
driver = GenerationCampaign.new(campaign)
driver.gate
dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=20261105-131145")
raise "Remaining selection differs" unless dry.include?("Dry run complete. The following 216 runs would have been executed:")
File.write(File.join(evidence, "dry-run.txt"), dry)
retained.each { |id, expected| raise "Pilot changed" unless hashes(File.join(manifest.fetch("persistent_results"), id)) == expected }
receipt = { "prepared_at" => Time.now.utc.iso8601, "source_commit" => commit, "runtime_root" => runtime,
  "full_campaign_authorized" => true, "priority_cutoff" => nil, "retained_pilot_files" => retained,
  "remaining_generation_observations" => 216, "inferences_launched_during_preparation" => 0,
  "authorization" => "User approved remaining 216 Ultra observations and completing the whole experiment before Fable; no need to yield for the weekly reset." }
File.write(File.join(evidence, "preparation.json"), JSON.pretty_generate(receipt) + "\n")
driver.snapshot("preflight_complete")
puts JSON.pretty_generate(receipt.except("retained_pilot_files"))
