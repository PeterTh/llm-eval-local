require "json"
require "digest"
require "fileutils"
require "open3"
require "time"
require "socket"
require_relative "/home/petert/llm_eval/experiment/lib/experiment_selection"

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

runtime = File.realpath(__dir__)
raise "Already prepared" if File.exist?(File.join(runtime, "campaign.path"))
repo = "/home/petert/llm_eval/experiment"
bench_repo = "/home/petert/llm_eval/benchmarks"
source_repo = "/home/petert/llm_para_experiments"
raise "Benchmark worktree not clean" unless checked("git", "-C", bench_repo, "status", "--porcelain").empty?
raise "Sequential baseline changed" unless checked("git", "-C", bench_repo, "rev-parse", "HEAD").strip == "2bc11aeac658a87b5cae25d03e0669f65d32922e"
raise "Staged source changes" unless checked("git", "-C", source_repo, "diff", "--cached", "--name-only").empty?
pids, pid_status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is busy: #{pids}" unless pid_status.exitstatus == 1 && pids.empty?
inspection = JSON.parse(checked("su", "-", "llmtest", "--shell=/bin/bash", "-c", "ruby #{runtime}/inspect_claude.rb"))
raise "Unexpected evaluation account configuration" unless inspection.fetch("extra_instruction_files").empty? &&
  inspection.fetch("custom_skills").empty? && !inspection.fetch("prior_outputs_readable") && inspection.fetch("credentials_readable")
binary = inspection.fetch("binary_path")
version = inspection.fetch("version")
raise "Unexpected CLI version #{version}" unless version == "2.1.296"
raise "Installed executable changed" unless inspection.fetch("binary_sha256") == "24972e3bc859fab2b46ed4c1e51f7d6130f06d3bd550811a114640de3370d0de"
profiles = ["claude-haiku-5.5-cc-medium"]
raise "Requested model differs" unless inspection.fetch("requested_model") == "claude-haiku-5-5"
fable_campaign = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium"
fable_pause = File.join(fable_campaign, "operator-pause.json")
raise "Fable is not intentionally paused" unless File.exist?(File.join(fable_campaign, "STOP")) && JSON.parse(File.read(fable_pause)).fetch("state") == "operator_paused"
benchmarks = %w[black-scholes cahn-hilliard cholesky floydwarshall matmul nbody qtclustering roomsim spmv stencil3d unstructured]
backends = %w[omp cuda mpi hybrid]
ids = ExperimentSelection.configurations(benchmarks: benchmarks, models: profiles, backends: backends, repetitions: 5).map { |c| ExperimentSelection.id(c) }
preflights = profiles.map { |profile| "black-scholes_#{profile}_omp_r1" }
batch = Time.now.utc.strftime("%Y%m%d-%H%M%S")
campaign = "/home/petert/llm_para_campaigns/#{batch}-haiku55-medium"
results = File.join(source_repo, batch)
raise "Campaign path already exists" if File.exist?(campaign) || File.exist?(results)
raise "Evaluation workspace already exists" if File.exist?("/home/llmtest/evals/#{batch}")
FileUtils.mkdir_p(campaign, mode: 0700)
FileUtils.mkdir_p(results)
File.write(File.join(runtime, "campaign.path"), campaign + "\n")
File.write(File.join(campaign, "campaign.path"), campaign + "\n")
archive(repo, File.join(campaign, "method"))
FileUtils.cp(File.join(repo, "experiment.rb"), File.join(campaign, "method", "experiment.rb"))
FileUtils.cp_r(File.join(campaign, "method"), File.join(runtime, "experiment"))
archive(bench_repo, File.join(runtime, "benchmarks"))
FileUtils.cp_r(File.join(runtime, "benchmarks"), File.join(campaign, "sequential-input"))
%w[run.rb monitor.rb FOLLOWUP.md inspect_claude.rb prepare.rb].each { |name| FileUtils.cp(File.join(runtime, name), File.join(campaign, name)) }
File.write(File.join(campaign, "claude-preflight.json"), JSON.pretty_generate(inspection) + "\n")
File.write(File.join(campaign, "run-ids.txt"), ids.join("\n") + "\n")
File.write(File.join(campaign, "preflight-ids.txt"), preflights.join("\n") + "\n")
manifest = { "schema_version" => 1, "campaign_id" => batch, "prepared_at" => Time.now.utc.iso8601,
  "phase" => "production_preflight", "host" => Socket.gethostname, "label" => "Haiku 5.5 medium",
  "source_repository" => "https://github.com/PeterTh/llm-eval-experiment", "source_commit" => checked("git", "-C", repo, "rev-parse", "HEAD").strip,
  "source_worktree_diff" => checked("git", "-C", repo, "diff", "--", "experiment.rb"),
  "source_note" => "The only uncommitted source changes are three pre-existing inactive Qwen lines, retained in this frozen snapshot but not selected.",
  "files" => hashes(File.join(runtime, "experiment")), "benchmark_files" => hashes(File.join(runtime, "benchmarks")),
  "sequential_source_repository" => "https://github.com/PeterTh/llm-eval-benchmarks",
  "sequential_source_commit" => checked("git", "-C", bench_repo, "rev-parse", "HEAD").strip,
  "harness" => "claude", "claude_version" => version, "claude_binary" => binary,
  "claude_binary_sha256" => inspection.fetch("binary_sha256"),
  "model" => profiles.first, "invoked_model" => "claude-haiku-5-5", "reasoning_effort" => "medium",
  "benchmarks" => benchmarks, "backends" => backends, "repetitions" => 5,
  "expected_runs" => ids.size, "per_run_timeout_seconds" => 14400, "preflight_ids" => preflights,
  "workspace" => "/home/llmtest/evals/#{batch}", "persistent_results" => results, "runtime_root" => runtime,
  "working_directory" => File.join(runtime, "experiment"), "source_branch" => checked("git", "-C", source_repo, "branch", "--show-current").strip,
  "initial_generated_source_commit" => checked("git", "-C", source_repo, "rev-parse", "HEAD").strip,
  "preflight_unit" => "llm-haiku55-preflight-#{batch}.service", "generation_unit" => "llm-haiku55-generation-#{batch}.service",
  "monitor_unit" => "llm-haiku55-monitor-#{batch}.service", "monitor_timer" => "llm-haiku55-monitor-#{batch}.timer",
  "paused_campaign" => { "path" => fable_campaign, "pause_receipt_sha256" => Digest::SHA256.file(fable_pause).hexdigest,
    "resume_not_before" => "2026-10-16T17:00:00Z", "constraint" => "Fable and Haiku must never run concurrently under llmtest." },
  "claude_version_reason" => "2.1.296 includes Haiku 5.5 support and the adaptive-thinking token-count fix. Fable remains pinned to its unchanged 2.1.287 executable.",
  "retention" => "Local NVMe runtime/workspaces; persistent outputs and provenance under home; no NFS workspace.",
  "reuse" => "The production-budget preflight is retained within the 220 observations, independent of generated-program correctness.",
  "monitoring" => "Serial observations; automatic metadata and cleanup checks between observations; approximately four-hour status timer after preflight.",
  "accounting" => "Exact final cumulative modelUsage counters; recorded retry backoff is excluded from generation elapsed and API times.",
  "lifecycle" => "Generation and original-source commit only, followed by validation, timing review/correction and established-size benchmarking." }
File.write(File.join(campaign, "campaign.json"), JSON.pretty_generate(manifest) + "\n")
dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=#{batch}")
File.write(File.join(campaign, "production-dry-run.txt"), dry)
raise "Dry-run scope differs" unless dry.include?("Total number of experiments to run: 220") && ids.all? { |id| dry.include?(id) }
raise "Production model or effort differs" unless dry.include?("--model claude-haiku-5-5 --effort medium") && dry.include?("Per-run wall clock limit: 240 minutes")
preflight_dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=#{batch}", "--run-ids=#{campaign}/preflight-ids.txt")
File.write(File.join(campaign, "preflight-dry-run.txt"), preflight_dry)
raise "Preflight dry-run scope differs" unless preflight_dry.include?("Total number of experiments to run: 1")
puts JSON.pretty_generate(manifest.slice("campaign_id", "expected_runs", "preflight_ids", "claude_version", "source_commit", "persistent_results", "runtime_root", "generation_unit"))
