# frozen_string_literal: true
# Run AFTER tested/committed tooling and the no-inference
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
deployment = JSON.parse(File.read("/home/petert/llm_para_campaigns/20261103-validation-strengthening/live-full-array-release-verification.json"))
raise "Latest publication incomplete" unless deployment.fetch("checked_build_shards_matched") && deployment.fetch("verified_new_exclusions") == 96
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
raise "Requested effort unavailable" unless model && model.fetch("supportedReasoningEfforts").any? { |entry| entry.fetch("reasoningEffort") == "ultra" }
features = JSON.parse(File.read(File.join(setup, "ultra-features.json")))
raise "Delegation unavailable" unless features.fetch("passed") && features.fetch("features").fetch("multi_agent")
native = JSON.parse(File.read(File.join(setup, "filesystem-preflight.json")))
raise "Native isolation probe failed" unless native.fetch("inferences_launched").zero? && native.fetch("lifecycle_exit_status").zero? && native.fetch("private_state_removed")
GenerationFilesystem.verify_evidence!(native.fetch("filesystem_isolation"), workspace: native.fetch("filesystem_isolation").fetch("workspace"))
binary = inspection.fetch("binary")
raise "CLI version differs" unless inspection.fetch("version") == "codex-cli 0.160.1" && native.fetch("version") == "0.160.1"
raise "CLI executable differs" unless Digest::SHA256.file(binary).hexdigest == native.fetch("binary_sha256")
raise "Filesystem method changed after preflight" unless Digest::SHA256.file(File.join(repo, "lib/generation_filesystem.rb")).hexdigest == native.fetch("filesystem_isolation").fetch("implementation_sha256")
native_companions = native.fetch("filesystem_isolation").fetch("harness_companions")
raise "Code-mode companion missing" unless native_companions.keys == ["codex-code-mode-host"]
companions = native_companions.to_h do |name, entry|
  raise "Wrong isolated companion mount" unless entry.fetch("mount") == "/run/llm-eval/bin/#{name}"
  [name, { "path" => File.join(File.dirname(binary), name), "sha256" => entry.fetch("sha256") }]
end
companions.each_value do |entry|
  raise "Companion changed after native preflight" unless Digest::SHA256.file(entry.fetch("path")).hexdigest == entry.fetch("sha256")
end
storage = %w[/tmp /home/llmtest/evals /home/petert/llm_para_experiments].to_h do |path|
  mounts = JSON.parse(checked("findmnt", "--json", "--target", path, "--output", "SOURCE,FSTYPE,TARGET")).fetch("filesystems")
  raise "Unrecognized workspace mount" unless mounts.size == 1 && %w[ext4 xfs btrfs tmpfs].include?(mounts.first.fetch("fstype"))
  [path, mounts.first]
end
profiles = { "gpt-6.1-terra-ultra" => { "model" => "gpt-6.1-terra", "reasoning_effort" => "ultra" } }
benchmarks = %w[black-scholes cahn-hilliard cholesky floydwarshall matmul nbody qtclustering roomsim spmv stencil3d unstructured]
backends = %w[omp cuda mpi hybrid]
ids = ExperimentSelection.configurations(benchmarks: benchmarks, models: profiles.keys, backends: backends, repetitions: 5).map { |c| ExperimentSelection.id(c) }
raise "Wrong scope" unless ids.size == 220
preflights = ["black-scholes_gpt-6.1-terra-ultra_omp_r1", "matmul_gpt-6.1-terra-ultra_cuda_r1",
  "spmv_gpt-6.1-terra-ultra_mpi_r1", "qtclustering_gpt-6.1-terra-ultra_hybrid_r1"]
batch = Time.now.utc.strftime("%Y%m%d-%H%M%S")
campaign = "/home/petert/llm_para_campaigns/#{batch}-terra61-codex-ultra"
results = File.join(source_repo, batch)
raise "Campaign path already exists" if File.exist?(campaign) || File.exist?(results)
runtime = Dir.mktmpdir("terra61-ultra-codex-generation-", "/tmp")
File.chmod(0755, runtime)
FileUtils.mkdir_p(campaign, mode: 0700)
FileUtils.mkdir_p(results)
archive(repo, File.join(runtime, "experiment"))
archive(bench_repo, File.join(runtime, "benchmarks"))
FileUtils.cp_r(File.join(runtime, "experiment"), File.join(campaign, "method"))
FileUtils.cp_r(File.join(runtime, "benchmarks"), File.join(campaign, "sequential-input"))
%w[run.rb controller.rb launch.rb inspect-model-access.rb prepare-campaign.rb check-preparation.rb commit-tooling.rb].each do |name|
  FileUtils.cp(File.join(setup, name), File.join(runtime, name))
  FileUtils.cp(File.join(setup, name), File.join(campaign, name))
end
%w[model-access.json filesystem-preflight.json regression-tests.log regression-tests.json ultra-features.json ultra-features.log tooling-commit.json].each { |name| FileUtils.cp(File.join(setup, name), campaign) }
[runtime, campaign, setup].each { |path| File.write(File.join(path, "campaign.path"), campaign + "\n") }
File.write(File.join(campaign, "run-ids.txt"), ids.join("\n") + "\n")
File.write(File.join(campaign, "preflight-ids.txt"), preflights.join("\n") + "\n")
manifest = {
  "schema_version" => 1, "campaign_id" => batch, "prepared_at" => Time.now.utc.iso8601,
  "phase" => "production_pilot_only", "host" => Socket.gethostname, "label" => "Terra 6.1 Ultra in Codex (native delegation)",
  "full_campaign_authorized" => false, "yield_at" => "2026-11-06T17:00:00Z",
  "source_repository" => "https://github.com/PeterTh/llm-eval-experiment",
  "source_commit" => checked("git", "-C", repo, "rev-parse", "HEAD").strip,
  "source_worktree_diff" => "", "source_note" => "Committed method snapshot; unrelated inactive Qwen edits are not included.",
  "files" => hashes(File.join(runtime, "experiment")), "benchmark_files" => hashes(File.join(runtime, "benchmarks")),
  "sequential_source_repository" => "https://github.com/PeterTh/llm-eval-benchmarks",
  "sequential_source_commit" => checked("git", "-C", bench_repo, "rev-parse", "HEAD").strip,
  "harness" => "codex", "codex_version" => "0.160.1", "codex_binary" => binary,
  "codex_binary_sha256" => native.fetch("binary_sha256"), "codex_sessions_root" => "/home/llmtest/.codex/sessions",
  "codex_companions" => companions, "storage" => storage,
  "generation_filesystem_policy" => GenerationFilesystem::POLICY,
  "models" => profiles, "benchmarks" => benchmarks, "backends" => backends, "repetitions" => 5,
  "expected_runs" => ids.size, "per_run_timeout_seconds" => 14400, "preflight_ids" => preflights,
  "workspace" => "/home/llmtest/evals/#{batch}", "persistent_results" => results, "runtime_root" => runtime,
  "working_directory" => File.join(runtime, "experiment"),
  "source_branch" => checked("git", "-C", source_repo, "branch", "--show-current").strip,
  "initial_generated_source_commit" => checked("git", "-C", source_repo, "rev-parse", "HEAD").strip,
  "preflight_unit" => "llm-terra61-ultra-pilot-#{batch}.service", "generation_unit" => "llm-terra61-ultra-generation-#{batch}.service",
  "retention" => "Local scratch/workspaces; persistent outputs and provenance under home. Fresh native sessions preserved without exposing prior sessions to agents.",
  "reuse" => "Four full-budget pilots are retained observations from the possible 220-run campaign; generated-program correctness is not a gate.",
  "monitoring" => "Active pilot checks, more closely near completion; no timer is assumed to notify the assistant.",
  "accounting" => "All fresh rollouts retained. Parent-only usage is not total Ultra usage. Review complete tree and inherited counters only after the pilot, with llmtest idle.",
  "delegation" => { "native" => true, "custom_child_models" => false, "custom_instructions" => false, "effective_cli_flags" => features.fetch("flags") },
  "priority" => "Fable safe-boundary priority at 2026-11-06T17:00Z. No automatic full Ultra campaign and no automatic quota-reset redemption.",
  "lifecycle" => "Commit originals; validation; static timing review/correction; affected revalidation; established benchmarking; winner review; cost/package/site publication."
}
File.write(File.join(campaign, "campaign.json"), JSON.pretty_generate(manifest) + "\n")
dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=#{batch}")
File.write(File.join(campaign, "production-dry-run.txt"), dry)
raise "Dry-run scope differs" unless dry.include?("Total number of experiments to run: 220") && ids.all? { |id| dry.include?(id) }
preflight_dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=#{batch}", "--run-ids=#{campaign}/preflight-ids.txt")
File.write(File.join(campaign, "preflight-dry-run.txt"), preflight_dry)
raise "Preflight dry-run scope differs" unless preflight_dry.include?("Total number of experiments to run: 4") && preflights.all? { |id| preflight_dry.include?(id) }
puts JSON.pretty_generate(manifest.slice("campaign_id", "expected_runs", "preflight_ids", "source_commit", "runtime_root", "generation_unit"))
