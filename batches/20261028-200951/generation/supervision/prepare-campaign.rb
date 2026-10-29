# frozen_string_literal: true
# Run AFTER Haiku publication, tested/committed tooling and the no-inference
# native filesystem preflight. This prepares only; it never launches inference.
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"
require "socket"
require "tmpdir"
require_relative "experiment/lib/experiment_selection"
require_relative "experiment/lib/generation_filesystem"

def checked(*command)
  output, error, status = Open3.capture3(*command)
  raise "#{command.first} failed: #{error}" unless status.success?
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

setup = File.realpath(__dir__)
raise "Campaign already prepared" if File.exist?(File.join(setup, "campaign.path"))
repo = File.join(setup, "experiment")
bench_repo = "/home/petert/llm_eval/benchmarks"
source_repo = "/home/petert/llm_para_experiments"
storage = ["/tmp", "/home/llmtest/evals", source_repo].to_h do |path|
  mount = JSON.parse(checked("findmnt", "--json", "--target", path, "--output", "SOURCE,FSTYPE,TARGET")).fetch("filesystems").fetch(0)
  raise "Nonlocal experiment storage: #{path}" unless %w[ext4 xfs btrfs tmpfs].include?(mount.fetch("fstype"))
  [path, mount]
end
haiku = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation"
publication = JSON.parse(File.read(File.join(haiku, "artifact-publication-push.json")))
# Supply the actual CI/live verification receipt after completing Haiku. No
# guessed publication state and no use of the old generation completion alone.
deployment = JSON.parse(File.read(ARGV.fetch(0)))
raise "Haiku deployment not verified" unless deployment.fetch("status") == "passed" && deployment.fetch("release_commit") == publication.fetch("release_commit")
raise "Tooling worktree not committed" unless checked("git", "-C", repo, "status", "--porcelain").empty?
raise "Benchmark worktree not clean" unless checked("git", "-C", bench_repo, "status", "--porcelain").empty?
raise "Staged source changes" unless checked("git", "-C", source_repo, "diff", "--cached", "--name-only").empty?
pids, pid_status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is busy" unless pid_status.exitstatus == 1 && pids.empty?
lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Native workload active" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
at_exit { lock.close }
tests = File.read(File.join(setup, "regression-tests.log"))
counts = tests.scan(/^(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips$/).last&.map(&:to_i)
raise "Missing passing regressions" unless counts && counts[0] >= 325 && counts[1] > 1800 && counts.drop(2) == [0, 0, 0]
inspection = JSON.parse(File.read(File.join(setup, "model-access.json")))
raise "Wrong subscription or additional instructions" unless inspection.fetch("auth_type") == "chatgpt" &&
  inspection.fetch("extra_instruction_or_hook_files").empty? && inspection.fetch("custom_provider_or_mcp_sections").empty?
model = inspection.fetch("requested_models").find { |m| m.fetch("model") == "gpt-6.1-terra" }
raise "Requested effort unavailable" unless model && model.fetch("supportedReasoningEfforts").any? { |entry| entry.fetch("reasoningEffort") == "medium" }
native = JSON.parse(File.read(File.join(setup, "filesystem-preflight.json")))
raise "Native isolation probe failed" unless native.fetch("inferences_launched").zero? && native.fetch("lifecycle_exit_status").zero? && native.fetch("private_state_removed")
GenerationFilesystem.verify_evidence!(native.fetch("filesystem_isolation"), workspace: native.fetch("filesystem_isolation").fetch("workspace"))
binary = inspection.fetch("binary")
raise "CLI version differs" unless inspection.fetch("version") == "codex-cli 0.160.1" && native.fetch("version") == "0.160.1"
raise "CLI executable differs" unless Digest::SHA256.file(binary).hexdigest == native.fetch("binary_sha256")
raise "Filesystem method changed after preflight" unless Digest::SHA256.file(File.join(repo, "lib/generation_filesystem.rb")).hexdigest == native.fetch("filesystem_isolation").fetch("implementation_sha256")
profiles = { "gpt-6.1-terra-medium" => { "model" => "gpt-6.1-terra", "reasoning_effort" => "medium" } }
benchmarks = %w[black-scholes cahn-hilliard cholesky floydwarshall matmul nbody qtclustering roomsim spmv stencil3d unstructured]
backends = %w[omp cuda mpi hybrid]
ids = ExperimentSelection.configurations(benchmarks: benchmarks, models: profiles.keys, backends: backends, repetitions: 5).map { |c| ExperimentSelection.id(c) }
raise "Wrong scope" unless ids.size == 220
preflights = ["black-scholes_gpt-6.1-terra-medium_omp_r1"]
batch = Time.now.utc.strftime("%Y%m%d-%H%M%S")
campaign = "/home/petert/llm_para_campaigns/#{batch}-terra61-codex-medium"
results = File.join(source_repo, batch)
raise "Campaign path already exists" if File.exist?(campaign) || File.exist?(results)
runtime = Dir.mktmpdir("terra61-codex-generation-", "/tmp")
File.chmod(0755, runtime)
FileUtils.mkdir_p(campaign, mode: 0700)
FileUtils.mkdir_p(results)
archive(repo, File.join(runtime, "experiment"))
archive(bench_repo, File.join(runtime, "benchmarks"))
FileUtils.cp_r(File.join(runtime, "experiment"), File.join(campaign, "method"))
FileUtils.cp_r(File.join(runtime, "benchmarks"), File.join(campaign, "sequential-input"))
%w[run.rb controller.rb monitor.rb inspect-model-access.rb prepare-campaign.rb launch.rb].each do |name|
  FileUtils.cp(File.join(setup, name), File.join(runtime, name))
  FileUtils.cp(File.join(setup, name), File.join(campaign, name))
end
%w[model-access.json filesystem-preflight.json regression-tests.log].each { |name| FileUtils.cp(File.join(setup, name), campaign) }
[runtime, campaign, setup].each { |path| File.write(File.join(path, "campaign.path"), campaign + "\n") }
File.write(File.join(campaign, "run-ids.txt"), ids.join("\n") + "\n")
File.write(File.join(campaign, "preflight-ids.txt"), preflights.join("\n") + "\n")
manifest = {
  "schema_version" => 1, "campaign_id" => batch, "prepared_at" => Time.now.utc.iso8601,
  "phase" => "production_preflight", "host" => Socket.gethostname, "label" => "Terra 6.1 medium in Codex",
  "source_repository" => "https://github.com/PeterTh/llm-eval-experiment",
  "source_commit" => checked("git", "-C", repo, "rev-parse", "HEAD").strip,
  "source_worktree_diff" => "", "source_note" => "Committed method snapshot; unrelated inactive Qwen edits are not included.",
  "files" => hashes(File.join(runtime, "experiment")), "benchmark_files" => hashes(File.join(runtime, "benchmarks")),
  "sequential_source_repository" => "https://github.com/PeterTh/llm-eval-benchmarks",
  "sequential_source_commit" => checked("git", "-C", bench_repo, "rev-parse", "HEAD").strip,
  "harness" => "codex", "codex_version" => "0.160.1", "codex_binary" => binary,
  "codex_binary_sha256" => native.fetch("binary_sha256"), "codex_sessions_root" => "/home/llmtest/.codex/sessions",
  "generation_filesystem_policy" => GenerationFilesystem::POLICY,
  "models" => profiles, "benchmarks" => benchmarks, "backends" => backends, "repetitions" => 5,
  "expected_runs" => ids.size, "per_run_timeout_seconds" => 14400, "preflight_ids" => preflights,
  "workspace" => "/home/llmtest/evals/#{batch}", "persistent_results" => results, "runtime_root" => runtime,
  "storage" => storage,
  "working_directory" => File.join(runtime, "experiment"),
  "source_branch" => checked("git", "-C", source_repo, "branch", "--show-current").strip,
  "initial_generated_source_commit" => checked("git", "-C", source_repo, "rev-parse", "HEAD").strip,
  "preflight_unit" => "llm-terra61-preflight-#{batch}.service", "generation_unit" => "llm-terra61-generation-#{batch}.service",
  "monitor_unit" => "llm-terra61-monitor-#{batch}.service", "monitor_timer" => "llm-terra61-monitor-#{batch}.timer",
  "retention" => "Local scratch/workspaces; persistent outputs and provenance under home. Fresh native sessions preserved without exposing prior sessions to agents.",
  "reuse" => "The full-budget preflight is one of the 220 retained observations; generated-program correctness is not a gate.",
  "monitoring" => "Active checks at most four hours apart, closer to completion; durable timer only records status.",
  "accounting" => "Exact session recovery after the pilot and after all generation, with account idle; no session scan during tuning.",
  "priority" => "Haiku OpenCode fully published first; Terra before Beam/other follow-up OpenCode. Fable safe-boundary reset priority at 2026-10-30T17:00Z retained.",
  "lifecycle" => "Commit originals; validation; static timing review/correction; affected revalidation; established benchmarking; winner review; cost/package/site publication."
}
File.write(File.join(campaign, "campaign.json"), JSON.pretty_generate(manifest) + "\n")
dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=#{batch}")
File.write(File.join(campaign, "production-dry-run.txt"), dry)
raise "Dry-run scope differs" unless dry.include?("Total number of experiments to run: 220") && ids.all? { |id| dry.include?(id) }
preflight_dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=#{batch}", "--run-ids=#{campaign}/preflight-ids.txt")
File.write(File.join(campaign, "preflight-dry-run.txt"), preflight_dry)
raise "Preflight dry-run scope differs" unless preflight_dry.include?("Total number of experiments to run: 1")
puts JSON.pretty_generate(manifest.slice("campaign_id", "expected_runs", "preflight_ids", "source_commit", "runtime_root", "generation_unit"))
