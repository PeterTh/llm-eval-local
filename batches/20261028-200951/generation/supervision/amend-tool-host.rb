# frozen_string_literal: true
require "json"
require "open3"
require "digest"
require "fileutils"
require "tmpdir"
require "time"

def checked(*args)
  output, error, status = Open3.capture3(*args)
  raise "#{args.first} failed: #{error}\n#{output}" unless status.success?
  output
end

def archive(repository, destination)
  FileUtils.mkdir_p(destination)
  statuses = Open3.pipeline(["git", "-C", repository, "archive", "HEAD"], ["tar", "-xf", "-", "-C", destination])
  raise "Snapshot extraction failed" unless statuses.all?(&:success?)
end

def hashes(directory)
  Dir[File.join(directory, "**", "*"), File.join(directory, "**", ".*")].uniq.sort.select { |p| File.file?(p) }.to_h do |path|
    [path.delete_prefix(directory + "/"), Digest::SHA256.file(path).hexdigest]
  end
end

setup = __dir__
campaign = File.read(File.join(setup, "campaign.path")).strip
manifest_path = File.join(campaign, "campaign.json")
original = JSON.parse(File.read(manifest_path))
raise "Wrong campaign" unless original.fetch("campaign_id") == "20261028-200951" && original.fetch("source_commit") == "73900953c086a4d3be7400616889920f57ed0bfc"
target = File.join(campaign, "tool-host-amendment.json")
raise "Already amended" if File.exist?(target)
raise "Full generation started" if File.exist?(File.join(campaign, "run-launch.json"))
unit = checked("systemctl", "--user", "show", original.fetch("preflight_unit"), "--property=ActiveState", "--value").strip
raise "Pilot is active" if %w[active activating deactivating].include?(unit)
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "llmtest busy" unless status.exitstatus == 1 && pids.empty?
lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Native host busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
at_exit { lock.close }
id = original.fetch("preflight_ids").fetch(0)
results = original.fetch("persistent_results")
raise "Unexpected completed observations" unless Dir.children(results) == [id] && Dir.children(File.join(campaign, "observations")) == ["#{id}.json"]
raise "Pilot was committed" unless checked("git", "-C", "/home/petert/llm_para_experiments", "ls-files", "--", original.fetch("campaign_id")).empty?
transcript = File.read(File.join(results, id, "output.txt"))
raise "Not the identified setup failure" unless transcript.include?("failed to spawn code-mode host /run/llm-eval/bin/codex-code-mode-host")
source = File.join(results, id, "black-scholes/black_scholes.cpp")
raise "Pilot changed program source" unless Digest::SHA256.file(source).hexdigest == original.fetch("benchmark_files").fetch("black-scholes/black_scholes.cpp")
repo = File.join(setup, "experiment")
raise "Uncommitted fix" unless checked("git", "-C", repo, "status", "--porcelain").empty?
revision = checked("git", "-C", repo, "rev-parse", "HEAD").strip
commit_receipt = JSON.parse(File.read("/home/petert/llm_para_campaigns/20261028-terra61-codex-preparation/tooling-companion-commit.json"))
raise "Fix not published" unless commit_receipt.fetch("published") && commit_receipt.fetch("commit") == revision
native = JSON.parse(File.read(File.join(setup, "filesystem-preflight-companion.json")))
raise "Companion probe failed" unless native.fetch("tool_host_startup").start_with?("passed:") && native.fetch("inferences_launched").zero?
tests = JSON.parse(File.read(File.join(setup, "regression-tests.json")))
raise "Regressions failed" unless tests.fetch("success") && tests.fetch("counts") == [329, 1908, 0, 0, 0]
runtime = Dir.mktmpdir("terra61-codex-generation-", "/tmp")
File.chmod(0755, runtime)
archive(repo, File.join(runtime, "experiment"))
archive("/home/petert/llm_eval/benchmarks", File.join(runtime, "benchmarks"))
raise "Sequential source changed" unless hashes(File.join(runtime, "benchmarks")) == original.fetch("benchmark_files")
attempt = File.join(campaign, "infrastructure-attempts/001-missing-code-mode-host")
raise "Attempt archive exists" if File.exist?(attempt)
FileUtils.mkdir_p(attempt)
FileUtils.cp(manifest_path, File.join(attempt, "campaign.json"))
program_hashes = hashes(File.join(results, id))
FileUtils.mv(File.join(results, id), File.join(attempt, "program"))
%W[preflight.log preflight-launch.json preflight-gate.json preflight-usage-recovery.json preflight-codex-usage.jsonl
  progress.json observations/#{id}.json cleanup/#{id}.json method regression-tests.log filesystem-preflight.json].each do |relative|
  destination = File.join(attempt, relative)
  FileUtils.mkdir_p(File.dirname(destination))
  FileUtils.mv(File.join(campaign, relative), destination)
end
review = {
  "checked_at" => Time.now.utc.iso8601, "passed" => false, "classification" => "infrastructure_failure",
  "reason" => "The CLI companion codex-code-mode-host was omitted from the filesystem allowlist. Both attempted tool calls failed before any program work.",
  "id" => id, "program_source_unchanged" => true, "program_files_sha256" => program_hashes,
  "excluded_from_experimental_observations" => true, "only_affected_pilot_repeated" => true,
  "exact_tokens_retained" => JSON.parse(File.read(File.join(attempt, "preflight-usage-recovery.json"))).fetch("total_tokens")
}
File.write(File.join(attempt, "review.json"), JSON.pretty_generate(review) + "\n")
FileUtils.cp_r(File.join(runtime, "experiment"), File.join(campaign, "method"))
%w[run.rb controller.rb monitor.rb launch.rb].each do |name|
  FileUtils.cp(File.join(campaign, name), File.join(attempt, name))
  FileUtils.cp(File.join(setup, name), File.join(runtime, name))
  FileUtils.cp(File.join(setup, name), File.join(campaign, name))
end
FileUtils.cp(File.join(setup, "regression-tests.log"), File.join(campaign, "regression-tests.log"))
FileUtils.cp(File.join(setup, "filesystem-preflight-companion.json"), File.join(campaign, "filesystem-preflight.json"))
File.write(File.join(runtime, "campaign.path"), campaign + "\n")
manifest = original.merge(
  "source_commit" => revision, "files" => hashes(File.join(runtime, "experiment")),
  "runtime_root" => runtime, "working_directory" => File.join(runtime, "experiment"),
  "preflight_unit" => "llm-terra61-preflight2-20261028-200951.service",
  "codex_companions" => { "codex-code-mode-host" => {
    "path" => File.join(File.dirname(original.fetch("codex_binary")), "codex-code-mode-host"),
    "sha256" => native.fetch("filesystem_isolation").fetch("harness_companions").fetch("codex-code-mode-host").fetch("sha256") } },
  "launcher_amendments" => ["tool-host-amendment.json"],
  "infrastructure_attempts" => ["infrastructure-attempts/001-missing-code-mode-host/review.json"])
File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
record = { "amended_at" => Time.now.utc.iso8601, "reason" => review.fetch("reason"),
  "original_source_commit" => original.fetch("source_commit"), "source_commit" => revision,
  "affected_ids" => [id], "valid_observations_repeated" => 0, "batch_changed" => false,
  "prompt_budget_model_effort_and_sequential_source_unchanged" => true,
  "prior_attempt" => "infrastructure-attempts/001-missing-code-mode-host", "runtime_root" => runtime,
  "tests" => tests.fetch("counts"), "native_preflight_sha256" => Digest::SHA256.file(File.join(setup, "filesystem-preflight-companion.json")).hexdigest,
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest }
File.write(target, JSON.pretty_generate(record) + "\n")
FileUtils.cp(__FILE__, File.join(campaign, File.basename(__FILE__)))
dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=20261028-200951", "--run-ids=#{campaign}/preflight-ids.txt")
raise "Amended pilot dry-run scope differs" unless dry.include?("Total number of experiments to run: 1")
File.write(File.join(campaign, "amended-preflight-dry-run.txt"), dry)
puts JSON.pretty_generate(record)
