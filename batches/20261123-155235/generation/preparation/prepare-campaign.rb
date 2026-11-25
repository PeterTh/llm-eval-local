# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"
require "socket"
require "tmpdir"
require "/home/petert/llm_eval/experiment/lib/experiment_selection"
require "/home/petert/llm_eval/experiment/lib/generation_filesystem"
require "/home/petert/llm_eval/experiment/lib/codex_model_catalog"
def checked(*command)
  out, err, status = Open3.capture3(*command)
  raise "#{command.first} failed: #{err}" unless status.success?
  out
end
def archive(repo, path)
  FileUtils.mkdir_p(path)
  statuses = Open3.pipeline(["git", "-C", repo, "archive", "HEAD"], ["tar", "-xf", "-", "-C", path])
  raise "Archive failed" unless statuses.all?(&:success?)
end
def hashes(root)
  files = Dir[File.join(root, "**", "*"), File.join(root, "**", ".*")].uniq.sort
  raise "Unexpected symlink" if files.any? { |path| File.symlink?(path) }
  files.select { |path| File.file?(path) }.to_h { |path| [path.delete_prefix(root + "/"), Digest::SHA256.file(path).hexdigest] }
end
setup = __dir__
raise "Already prepared" if File.exist?(File.join(setup, "campaign.path"))
repo = "/home/petert/llm_eval/experiment"
bench_repo = "/home/petert/llm_eval/benchmarks"
sources = "/home/petert/llm_para_experiments"
read = ->(name) { JSON.parse(File.read(File.join(setup, name + ".json"))) }
tooling = read.call("tooling-commit")
raise "Uncommitted method" unless checked("git", "-C", repo, "rev-parse", "HEAD").strip == tooling.fetch("commit") && checked("git", "-C", repo, "diff", "--cached", "--name-only").empty?
raise "Unpublished method" unless checked("git", "-C", repo, "ls-remote", "--exit-code", "origin", "refs/heads/codex").strip == "#{tooling.fetch('commit')}\trefs/heads/codex"
raise "Dirty benchmark inputs" unless checked("git", "-C", bench_repo, "status", "--porcelain").empty?
raise "Benchmark programs changed upstream" unless checked("git", "-C", bench_repo, "diff", "--name-only", "2bc11aeac658a87b5cae25d03e0669f65d32922e", "HEAD").lines.map(&:strip) == ["README.md"]
raise "Staged generated sources" unless checked("git", "-C", sources, "diff", "--cached", "--name-only").empty?
pids, pid_status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account busy" unless pid_status.exitstatus == 1 && pids.empty?
lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
at_exit { lock.close }
native = read.call("filesystem-preflight")
raise "Native probe failed" unless native.fetch("inferences_launched").zero? && native.fetch("lifecycle_exit_status").zero? && native.fetch("private_state_removed")
GenerationFilesystem.verify_evidence!(native.fetch("filesystem_isolation"), workspace:native.fetch("filesystem_isolation").fetch("workspace"))
raise "Method changed after probe" unless native.fetch("filesystem_isolation").fetch("implementation_sha256") == Digest::SHA256.file(File.join(repo, "lib/generation_filesystem.rb")).hexdigest
access = read.call("model-access")
raise "Wrong authentication/configuration" unless access.fetch("auth_type") == "chatgpt" && access.fetch("extra_instruction_or_hook_files").empty? && access.fetch("custom_provider_or_mcp_sections").empty?
raise "Wrong version" unless access.fetch("version") == "codex-cli 0.171.0" && native.fetch("version") == "0.171.0"
profiles = %w[astra sol].to_h { |family| ["gpt-6.2-#{family}-medium", {"model"=>"gpt-6.2-#{family}", "reasoning_effort"=>"medium"}] }
profiles.each_value do |profile|
  model = access.fetch("requested_models").find { |entry| entry.fetch("model") == profile.fetch("model") }
  raise "Medium unavailable" unless model && model.fetch("supportedReasoningEfforts").any? { |entry| entry.fetch("reasoningEffort") == "medium" }
end
raise "Restrictions failed" unless read.call("features").fetch("passed")
tests = read.call("regression-tests")
raise "Tests failed" unless tests.fetch("success") && tests.fetch("counts").first >= 525 && tests.fetch("counts").drop(2) == [0,0,0]
catalog = read.call("catalog")
catalog_path = catalog.fetch("path")
catalog_receipt = JSON.parse(File.read(catalog_path + ".receipt.json"))
profiles.each_value { |profile| CodexModelCatalog.verify!(File.read(catalog_path), catalog_receipt, version:"0.171.0", model:profile.fetch("model"), effort:"medium") }
storage = %w[/tmp /home/llmtest/evals /home/petert/llm_para_experiments].to_h do |path|
  mount = JSON.parse(checked("findmnt", "--json", "--target", path, "--output", "SOURCE,FSTYPE,TARGET")).fetch("filesystems").fetch(0)
  raise "Non-local storage" unless %w[ext4 xfs btrfs tmpfs].include?(mount.fetch("fstype"))
  [path, mount]
end
benchmarks = %w[black-scholes cahn-hilliard cholesky floydwarshall matmul nbody qtclustering roomsim spmv stencil3d unstructured]
backends = %w[omp cuda mpi hybrid]
ids = ExperimentSelection.configurations(benchmarks:benchmarks, models:profiles.keys, backends:backends, repetitions:5).map { |config| ExperimentSelection.id(config) }
raise "Wrong scope" unless ids.size == 440
preflights = profiles.keys.map { |profile| "black-scholes_#{profile}_omp_r1" }
batch = Time.now.utc.strftime("%Y%m%d-%H%M%S")
campaign = "/home/petert/llm_para_campaigns/#{batch}-gpt62-astra-sol-medium"
results = File.join(sources, batch)
raise "Existing campaign" if File.exist?(campaign) || File.exist?(results)
runtime = Dir.mktmpdir("gpt62-medium-generation-", "/tmp")
File.chmod(0755, runtime)
FileUtils.mkdir_p(campaign, mode:0700)
FileUtils.mkdir_p(results)
archive(repo, File.join(runtime, "experiment"))
archive(bench_repo, File.join(runtime, "benchmarks"))
FileUtils.cp_r(File.join(runtime, "experiment"), File.join(campaign, "method"))
FileUtils.cp_r(File.join(runtime, "benchmarks"), File.join(campaign, "sequential-input"))
%w[run.rb controller.rb monitor.rb launch.rb].each do |name|
  FileUtils.cp(File.join(setup, name), runtime)
  FileUtils.cp(File.join(setup, name), campaign)
end
preparation = File.join(campaign, "preparation")
FileUtils.mkdir_p(preparation)
Dir[File.join(setup, "*.rb"), File.join(setup, "*.json"), File.join(setup, "*.log"), File.join(setup, "*.patch")].each { |path| FileUtils.cp(path, preparation) }
FileUtils.cp(catalog_path, File.join(runtime, "model-catalog.json"))
FileUtils.cp(catalog_path + ".receipt.json", File.join(runtime, "model-catalog.json.receipt.json"))
FileUtils.cp(catalog_path, File.join(campaign, "model-catalog.json"))
FileUtils.cp(catalog_path + ".receipt.json", File.join(campaign, "model-catalog.json.receipt.json"))
File.write(File.join(campaign, "run-ids.txt"), ids.join("\n") + "\n")
File.write(File.join(campaign, "preflight-ids.txt"), preflights.join("\n") + "\n")
[runtime, campaign, setup].each { |path| File.write(File.join(path, "campaign.path"), campaign + "\n") }
binary = access.fetch("binary")
companions = native.fetch("filesystem_isolation").fetch("harness_companions").to_h { |name,row| [name,{"path"=>File.join(File.dirname(binary),name), "sha256"=>row.fetch("sha256")}] }
manifest = {"schema_version"=>1, "campaign_id"=>batch, "prepared_at"=>Time.now.utc.iso8601, "phase"=>"production_preflight",
  "full_campaign_authorized"=>true, "host"=>Socket.gethostname, "label"=>"Astra 6.2 and Sol 6.2 Medium in Codex",
  "source_repository"=>"https://github.com/PeterTh/llm-eval-experiment", "source_commit"=>tooling.fetch("commit"),
  "source_worktree_diff"=>"", "source_note"=>"Committed snapshot; unrelated pre-existing inactive Qwen edits excluded and preserved.",
  "files"=>hashes(File.join(runtime,"experiment")), "benchmark_files"=>hashes(File.join(runtime,"benchmarks")),
  "sequential_source_repository"=>"https://github.com/PeterTh/llm-eval-benchmarks", "sequential_source_commit"=>checked("git","-C",bench_repo,"rev-parse","HEAD").strip,
  "benchmark_input_changes_from_previous_campaign"=>[], "upstream_documentation_changes"=>["README.md"],
  "artifact_baseline"=>checked("git","-C","/home/petert/llm-eval-local","rev-parse","HEAD").strip,
  "harness"=>"codex", "codex_version"=>"0.171.0", "codex_binary"=>binary, "codex_binary_sha256"=>native.fetch("binary_sha256"),
  "codex_companions"=>companions, "codex_sessions_root"=>"/home/llmtest/.codex/sessions", "storage"=>storage,
  "codex_model_catalog"=>{"path"=>File.join(runtime,"model-catalog.json"), "sha256"=>Digest::SHA256.file(catalog_path).hexdigest, "receipt_sha256"=>Digest::SHA256.file(catalog_path+".receipt.json").hexdigest},
  "generation_filesystem_policy"=>GenerationFilesystem::POLICY, "models"=>profiles, "benchmarks"=>benchmarks, "backends"=>backends,
  "repetitions"=>5, "expected_runs"=>440, "per_run_timeout_seconds"=>14400, "preflight_ids"=>preflights,
  "workspace"=>"/home/llmtest/evals/#{batch}", "persistent_results"=>results, "runtime_root"=>runtime, "working_directory"=>File.join(runtime,"experiment"),
  "source_branch"=>checked("git","-C",sources,"branch","--show-current").strip,
  "initial_generated_source_commit"=>checked("git","-C",sources,"rev-parse","HEAD").strip,
  "preflight_unit"=>"llm-gpt62-medium-preflight-#{batch}.service", "generation_unit"=>"llm-gpt62-medium-generation-#{batch}.service",
  "monitor_unit"=>"llm-gpt62-medium-monitor-#{batch}.service", "monitor_timer"=>"llm-gpt62-medium-monitor-#{batch}.timer",
  "orchestration_files"=>%w[run.rb controller.rb monitor.rb].to_h { |name| [name,Digest::SHA256.file(File.join(runtime,name)).hexdigest] },
  "retention"=>"Local scratch and workspaces; persistent evidence and originals in home; no NFS builds.",
  "reuse"=>"One production-budget observation per model; both retained within 440, independent of program correctness.",
  "monitoring"=>"Metadata/cleanup checks after every observation; four-hour read-only status checks. Timer does not itself wake an assistant.",
  "accounting"=>"Exact session accounting at the two-observation preflight gate and after all generation, while llmtest is idle.",
  "delegation"=>{"native"=>false}, "priority"=>"User-requested Astra/Sol 6.2 campaign; GLM remains suspended.",
  "lifecycle"=>"Preserve originals; validation; timing review/correction; affected revalidation; established-size benchmarking; winner reviews; pricing/package/site integration."}
File.write(File.join(campaign,"campaign.json"), JSON.pretty_generate(manifest)+"\n")
dry = checked("ruby",File.join(runtime,"run.rb"),"--production","--continue=#{batch}")
raise "Dry-run scope mismatch" unless dry.include?("Total number of experiments to run: 440") && ids.all? { |id| dry.include?(id) }
File.write(File.join(campaign,"production-dry-run.txt"),dry)
pilot = checked("ruby",File.join(runtime,"run.rb"),"--production","--continue=#{batch}","--run-ids=#{campaign}/preflight-ids.txt")
raise "Pilot scope mismatch" unless pilot.include?("Total number of experiments to run: 2") && preflights.all? { |id| pilot.include?(id) }
File.write(File.join(campaign,"preflight-dry-run.txt"),pilot)
puts JSON.pretty_generate(manifest.slice("campaign_id","expected_runs","preflight_ids","runtime_root","source_commit","generation_unit"))
