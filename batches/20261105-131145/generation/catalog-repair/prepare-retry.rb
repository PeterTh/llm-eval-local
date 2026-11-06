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
  raise "Linked data require review" if paths.any? { |path| File.symlink?(path) }
  paths.select { |path| File.file?(path) }.to_h { |path| [path.delete_prefix(root + "/"), Digest::SHA256.file(path).hexdigest] }
end

setup = __dir__
campaign = "/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra"
repair = File.join(campaign, "catalog-repair-20261105")
raise "Repair already prepared" if File.exist?(repair)
manifest_path = File.join(campaign, "campaign.json")
original = JSON.parse(File.read(manifest_path))
target_id = "matmul_gpt-6.1-terra-ultra_cuda_r1"
raise "Wrong campaign" unless original.fetch("campaign_id") == "20261105-131145" && original.fetch("full_campaign_authorized") == false
raise "Pilot scope changed" unless original.fetch("preflight_ids").size == 4 && original.fetch("preflight_ids").include?(target_id)
raise "Fable priority reached" if Time.now >= Time.iso8601(original.fetch("yield_at"))
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
host_lock = File.open("/tmp/local-evaluation-#{Process.uid}-performance.lock", "a")
raise "Host busy" unless host_lock.flock(File::LOCK_EX | File::LOCK_NB)
controller_lock = File.open(File.join(campaign, "controller.lock"), "a")
raise "Controller busy" unless controller_lock.flock(File::LOCK_EX | File::LOCK_NB)
repo = File.join(setup, "experiment")
raise "Uncommitted method" unless checked("git", "-C", repo, "status", "--porcelain").empty?
commit = JSON.parse(File.read(File.join(setup, "tooling-commit.json"))).fetch("commit")
raise "Wrong method" unless checked("git", "-C", repo, "rev-parse", "HEAD").strip == commit
native = JSON.parse(File.read(File.join(setup, "filesystem-preflight.json")))
raise "Native check failed" unless native.fetch("inferences_launched").zero? && native.fetch("private_state_removed")
receipt_path = File.join(setup, "capture/models-verified.json.receipt.json")
receipt = JSON.parse(File.read(receipt_path))
raise "Catalog checks failed" unless %w[offline_native_schema_check native_cache_absent_during_offline_check missing_catalog_rejected read_only_mount_verified].all? { |key| receipt.fetch(key) }
raise "Metadata changed" unless JSON.parse(File.read(File.join(setup, "catalog-baseline-comparison.json"))).fetch("matches_pre_pilot_native_catalog")
source_repo = File.dirname(original.fetch("persistent_results"))
raise "Existing staged source work" unless checked("git", "-C", source_repo, "diff", "--cached", "--name-only").empty?
target = File.join(original.fetch("persistent_results"), target_id)
raise "Target already tracked; preserve its commit first" unless checked("git", "-C", source_repo, "ls-files", "--", "20261105-131145/#{target_id}").empty?
raise "Wrong retry target" unless File.read(File.join(target, "output.txt"), 8192).include?("Defaulting to fallback metadata")
retained = (original.fetch("preflight_ids") - [target_id]).to_h { |id| [id, hashes(File.join(original.fetch("persistent_results"), id))] }
superseded = hashes(target)
FileUtils.mkdir_p(repair, mode: 0700)
FileUtils.cp(manifest_path, File.join(repair, "campaign.before-repair.json"))
FileUtils.cp(File.join(campaign, "progress.json"), File.join(repair, "progress.before-repair.json"))
FileUtils.cp(File.join(campaign, "preflight-review.json"), File.join(repair, "preflight-review.before-repair.json"))
FileUtils.cp_r(File.join(setup, "capture"), File.join(repair, "catalog-captures"))
%w[filesystem-preflight.json filesystem-preflight.log catalog-baseline-comparison.json regression-tests.log regression-tests.json tooling-commit.json check-native.rb commit-tooling.rb prepare-retry.rb run.rb retry-controller.rb launch-retry.rb].each do |name|
  FileUtils.cp(File.join(setup, name), repair)
end
runtime = Dir.mktmpdir("terra61-ultra-catalog-retry-", "/tmp")
File.chmod(0755, runtime)
FileUtils.mkdir_p(File.join(runtime, "experiment"))
statuses = Open3.pipeline(["git", "-C", repo, "archive", "HEAD"], ["tar", "-xf", "-", "-C", File.join(runtime, "experiment")])
raise "Method extraction failed" unless statuses.all?(&:success?)
FileUtils.cp_r(File.join(campaign, "sequential-input"), File.join(runtime, "benchmarks"))
raise "Sequential input changed" unless hashes(File.join(runtime, "benchmarks")) == original.fetch("benchmark_files")
FileUtils.cp_r(File.join(runtime, "experiment"), File.join(repair, "method"))
FileUtils.cp(File.join(setup, "capture/models-verified.json"), File.join(runtime, "model-catalog.json"))
FileUtils.cp(receipt_path, File.join(runtime, "model-catalog.json.receipt.json"))
%w[run.rb retry-controller.rb launch-retry.rb].each { |name| FileUtils.cp(File.join(setup, name), File.join(runtime, name)) }
File.write(File.join(runtime, "campaign.path"), campaign + "\n")
File.write(File.join(repair, "campaign.path"), campaign + "\n")
File.write(File.join(setup, "campaign.path"), campaign + "\n")
backup = File.join(repair, "superseded", target_id)
FileUtils.mkdir_p(File.dirname(backup))
raise "Archive is not on the same filesystem" unless File.stat(target).dev == File.stat(File.dirname(backup)).dev
File.rename(target, backup)
raise "Preserved attempt differs" unless hashes(backup) == superseded
%w[observations cleanup].each do |name|
  FileUtils.mkdir_p(File.join(repair, "superseded", name))
  File.rename(File.join(campaign, name, "#{target_id}.json"), File.join(repair, "superseded", name, "#{target_id}.json"))
end
manifest = original.merge(
  "phase" => "production_pilot_catalog_retry", "source_commit" => commit, "files" => hashes(File.join(runtime, "experiment")),
  "runtime_root" => runtime, "working_directory" => File.join(runtime, "experiment"),
  "catalog_repair_root" => repair, "catalog_retry_id" => target_id,
  "catalog_retry_unit" => "llm-terra61-ultra-catalog-retry-20261105-131145.service",
  "codex_model_catalog" => { "path" => File.join(runtime, "model-catalog.json"),
    "persistent_path" => File.join(repair, "catalog-captures/models-verified.json"),
    "sha256" => receipt.fetch("catalog_sha256"), "receipt_sha256" => Digest::SHA256.file(receipt_path).hexdigest },
  "method_revisions" => [
    { "commit" => original.fetch("source_commit"), "method_root" => File.join(campaign, "method"), "retained_ids" => retained.keys },
    { "commit" => commit, "method_root" => File.join(repair, "method"), "scope" => "Targeted CUDA retry and any later authorized observations", "metadata_definitions_unchanged" => true } ])
File.write(manifest_path + ".tmp", JSON.pretty_generate(manifest) + "\n")
File.rename(manifest_path + ".tmp", manifest_path)
File.write(File.join(repair, "retry-ids.txt"), target_id + "\n")
repair_receipt = { "prepared_at" => Time.now.utc.iso8601, "target_id" => target_id,
  "reason" => "Native model-catalog download timeout led to fallback metadata", "original_attempt" => backup,
  "original_files" => superseded, "retained_other_observations" => retained,
  "method_commit" => commit, "metadata_definitions_unchanged" => true,
  "full_campaign_authorized" => false, "runtime_root" => runtime }
File.write(File.join(repair, "repair.json"), JSON.pretty_generate(repair_receipt) + "\n")
dry = checked("ruby", File.join(runtime, "run.rb"), "--production", "--continue=20261105-131145", "--run-ids=#{repair}/retry-ids.txt")
raise "Retry dry-run scope differs" unless dry.include?("Total number of experiments to run: 1") && dry.include?(target_id)
File.write(File.join(repair, "retry-dry-run.txt"), dry)
puts JSON.pretty_generate(repair_receipt.slice("target_id", "original_attempt", "method_commit", "full_campaign_authorized", "runtime_root"))
