require "json"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"
require "time"

REPO = "/home/petert/llm_eval/experiment"
CONTROLLER = "/tmp/opencode-go-output-limit-controller-20261021.F2iMc4"
COMMIT = "8af32415270916c4c094f1bfd61b45c9e8eb5da4"
QUEUE = "/home/petert/llm_para_campaigns/20261019-134152-opencode-go-queue"
EVIDENCE = File.join(QUEUE, "amendments/20261021-advertised-output-limits")
SOURCE_REPO = "/home/petert/llm_para_experiments"
ARCHIVE_REL = "superseded/20261019-134042/output-limit-32000"
IDS = %w[cholesky_deepseek-v4.1-flash-oc-high_cuda_r2
  cholesky_deepseek-v4.1-flash-oc-high_mpi_r3
  floydwarshall_deepseek-v4.1-flash-oc-high_hybrid_r2
  roomsim_deepseek-v4.1-flash-oc-high_hybrid_r2].freeze

def checked(*command)
  out, err, status = Open3.capture3(*command)
  raise "#{command.first} failed: #{err}\n#{out}" unless status.success?
  out
end

def write(path, data)
  File.write(path, JSON.pretty_generate(data) + "\n")
end

def hashes(root)
  Dir[File.join(root, "**", "*"), File.join(root, "**", ".*")].uniq.sort.filter_map do |path|
    next unless File.file?(path)
    raise "Unexpected symlink: #{path}" if File.symlink?(path)
    [path.delete_prefix(root + "/"), Digest::SHA256.file(path).hexdigest]
  end.to_h
end

require File.join(CONTROLLER, "tools/opencode_campaign_queue")
raise "Commit differs" unless checked("git", "-C", REPO, "rev-parse", "HEAD").strip == COMMIT
raise "Existing amendment must be reviewed, not overwritten" if File.exist?(EVIDENCE)
raise "Archive already exists" if File.exist?(File.join(SOURCE_REPO, ARCHIVE_REL))
queue_path = File.join(QUEUE, "queue.json")
queue = JSON.parse(File.read(queue_path))
raise "Queue active" if checked("systemctl", "--user", "show", queue.fetch("generation_unit"), "-p", "ActiveState", "--value").strip == "active"
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
raise "Queue STOP present" if File.exist?(File.join(QUEUE, "STOP"))
raise "Existing staged user changes" unless checked("git", "-C", SOURCE_REPO, "diff", "--cached", "--name-only").empty?
raise "Wrong generated-source branch" unless checked("git", "-C", SOURCE_REPO, "branch", "--show-current").strip == "claude"
tests_path = "/tmp/opencode-go-output-cap-regression-20261021.log"
counts = File.read(tests_path).scan(/^(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips$/).last&.map(&:to_i)
raise "Regression tests differ" unless counts == [293, 1693, 0, 0, 0]
inspection_path = "/tmp/opencode-limit-preflight-20261021.log"
inspections = JSON.parse(File.readlines(inspection_path).last).fetch("configuration_inspections")
raise "Missing native configuration checks" unless inspections.map { |r| r.fetch("model") } == OpenCodeHarness::GO_OUTPUT_TOKEN_LIMITS.keys
inspections.each do |row|
  raise "Unexpected inference" unless row.fetch("inferences_launched").zero?
  raise "Inspected policy differs" unless row.fetch("policy") == OpenCodeHarness.output_token_policy(row.fetch("model"))
end
manifests = queue.fetch("campaigns").to_h do |path|
  value = JSON.parse(File.read(File.join(path, "campaign.json")))
  value.fetch("files").each do |relative, sha|
    raise "Original runtime changed: #{relative}" unless Digest::SHA256.file(File.join(value.fetch("working_directory"), relative)).hexdigest == sha
  end
  raise "Campaign stopped by operator" if File.exist?(File.join(path, "STOP"))
  raise "Fable pause missing" unless File.file?(File.join(value.fetch("paused_campaign").fetch("path"), "STOP"))
  [path, value]
end
deepseek = queue.fetch("campaigns").first
results = manifests.fetch(deepseek).fetch("persistent_results")
incident_path = File.join(deepseek, "incidents/20261021-output-token-limit/incident.json")
incident = JSON.parse(File.read(incident_path))
raise "Incident scope differs" unless incident.fetch("affected_observations").map { |r| r.fetch("id") }.sort == IDS.sort
affected, context_counts = [], []
sessions = Dir[File.join(results, "*/opencode-session.txt")]
sessions.each do |path|
  session = JSON.parse(File.read(path))
  assistants = session.fetch("messages").map { |m| m.fetch("info") }.select { |h| h["role"] == "assistant" }
  affected << File.basename(File.dirname(path)) if assistants.any? { |h| h["finish"] == "length" }
  assistants.each do |h|
    next unless h["tokens"]
    t = h.fetch("tokens")
    context_counts << (t["total"] || t.values_at("input", "output").sum + t.fetch("cache").values.sum)
  end
end
raise "Affected scope changed" unless sessions.size == 113 && affected.sort == IDS.sort
raise "Additional compaction-affected observation" unless context_counts.max < 616_000
incident.fetch("affected_observations").each do |row|
  raise "Incident session changed" unless Digest::SHA256.file(File.join(results, row.fetch("id"), "opencode-session.txt")).hexdigest == row.fetch("session_sha256")
end
original_reports = Dir[File.join(deepseek, "observations/*.json")].to_h { |p| [File.basename(p, ".json"), JSON.parse(File.read(p))] }
raise "Admitted scope differs" unless original_reports.size == 112
original_reports.each do |id, old|
  current = OpenCodeGenerationObservation.read(File.join(results, id), model: old.fetch("model"), effort: old.fetch("reasoning_effort"))
  raise "Admitted observation changed: #{id}" unless old == current
end
original_hashes = IDS.to_h { |id| [id, hashes(File.join(results, id))] }
FileUtils.mkdir_p(EVIDENCE, mode: 0700)
FileUtils.cp(queue_path, File.join(EVIDENCE, "queue-before.json"))
FileUtils.cp(__FILE__, File.join(EVIDENCE, "amend.rb"))
FileUtils.cp(tests_path, File.join(EVIDENCE, "regression-tests.log"))
FileUtils.cp(inspection_path, File.join(EVIDENCE, "native-configuration-checks.log"))
FileUtils.cp("/tmp/opencode-limit-preflight-20261021.rb", File.join(EVIDENCE, "inspect.rb"))
FileUtils.cp_r(CONTROLLER, File.join(EVIDENCE, "method"))
write(File.join(EVIDENCE, "unchanged-observations.json"), original_reports.reject { |id, _| IDS.include?(id) })
write(File.join(EVIDENCE, "original-attempt-file-hashes.json"), original_hashes)
prepared = manifests.map.with_index do |(path, manifest), index|
  FileUtils.cp(File.join(path, "campaign.json"), File.join(EVIDENCE, "campaign-#{index}-before.json"))
  runtime = Dir.mktmpdir("opencode-go-advertised-limit-#{index}-", "/tmp")
  FileUtils.chmod(0755, runtime)
  FileUtils.cp_r(CONTROLLER, File.join(runtime, "experiment"))
  FileUtils.cp_r(File.join(manifest.fetch("runtime_root"), "benchmarks"), File.join(runtime, "benchmarks"))
  FileUtils.cp(manifest.fetch("opencode_binary"), File.join(runtime, "opencode"), preserve: true)
  FileUtils.cp(File.join(CONTROLLER, "tools/run_opencode_campaign.rb"), File.join(runtime, "run.rb"))
  File.write(File.join(runtime, "campaign.path"), path + "\n")
  raise "Sequential inputs changed" unless hashes(File.join(runtime, "benchmarks")) == manifest.fetch("benchmark_files")
  raise "Binary changed" unless Digest::SHA256.file(File.join(runtime, "opencode")).hexdigest == OpenCodeHarness::BINARY_SHA256
  profile = manifest.fetch("models").values.fetch(0)
  revised = manifest.merge("runtime_root" => runtime, "working_directory" => File.join(runtime, "experiment"),
    "opencode_binary" => File.join(runtime, "opencode"), "files" => hashes(File.join(runtime, "experiment")),
    "runtime_source_commit" => COMMIT, "opencode_output_token_policy" => OpenCodeHarness.output_token_policy(profile.fetch("model")),
    "runtime_amendment" => { "path" => EVIDENCE, "reason" => "Use advertised model output allowance; rerun only the four observed 32000-cap hits",
      "approved_by" => "user", "superseded_source_path" => index.zero? ? ARCHIVE_REL : nil,
      "affected_observations" => index.zero? ? IDS : [], "original_source_commit" => manifest.fetch("source_commit") })
  [path, revised]
end
archive = File.join(SOURCE_REPO, ARCHIVE_REL)
FileUtils.mkdir_p(archive)
FileUtils.cp(incident_path, File.join(archive, "incident.txt"))
IDS.each do |id|
  FileUtils.mv(File.join(results, id), File.join(archive, id))
  raise "Moved attempt changed" unless hashes(File.join(archive, id)) == original_hashes.fetch(id)
  %w[observations cleanup quota].each do |kind|
    prior = File.join(deepseek, kind, "#{id}.json")
    next unless File.file?(prior)
    FileUtils.mkdir_p(File.join(EVIDENCE, "original-#{kind}"))
    saved = File.join(EVIDENCE, "original-#{kind}", "#{id}.json")
    kind == "observations" ? FileUtils.mv(prior, saved) : FileUtils.cp(prior, saved)
  end
end
receipt = { "schema_version" => 1, "recorded_at" => Time.now.utc.iso8601,
  "decision" => "User-approved advertised model limits and reruns only of observations that hit the lower harness cap",
  "reason" => "harness_response_output_limit", "source_commit" => COMMIT,
  "old_per_response_cap" => 32_000, "new_limits" => OpenCodeHarness::GO_OUTPUT_TOKEN_LIMITS,
  "affected_observations" => IDS, "superseded_attempts" => ARCHIVE_REL,
  "replacement_batch" => "20261019-134042", "originals_used_in_final_analysis" => false,
  "replacement_selection" => "Exactly one fresh attempt per affected ID, regardless of its correctness or performance; no best-of selection",
  "unchanged_observations" => original_reports.size - 3, "attempts_scanned" => sessions.size,
  "compaction_check" => { "maximum_historical_counter" => context_counts.max, "new_deepseek_boundary" => 616_000, "additional_affected_observations" => 0 },
  "model_caused_termination_preserved_without_retry" => "qtclustering_deepseek-v4.1-flash-oc-high_mpi_r2",
  "tests" => %w[runs assertions failures errors skips].zip(counts).to_h,
  "native_configuration_preflight" => inspections.map { |r| r.slice("model", "policy", "inferences_launched", "checked_at") },
  "superseded_file_hashes" => original_hashes }
write(File.join(archive, "supersession.txt"), receipt)
checked("git", "-C", SOURCE_REPO, "add", "--", ARCHIVE_REL)
staged = checked("git", "-C", SOURCE_REPO, "diff", "--cached", "--name-only", "-z").split("\0")
raise "Archive staging scope differs" unless staged.all? { |p| p.start_with?(ARCHIVE_REL + "/") } && staged.size == 50
entries = checked("git", "-C", SOURCE_REPO, "ls-files", "--stage", "--", ARCHIVE_REL).lines
raise "Non-regular staged source" unless entries.all? { |row| row.start_with?("100644 ", "100755 ") }
IDS.each do |id|
  (%w[output.txt timing.txt instruction.txt process-status.txt] + OpenCodeHarness::EVIDENCE_FILES).each do |name|
    raise "Archive metadata ignored" unless staged.include?("#{ARCHIVE_REL}/#{id}/#{name}")
  end
end
raise "Build artifacts included" if staged.any? { |p| p.match?(%r{/(?:build[^/]*|CMakeFiles|\.git)/}) || File.binread(File.join(SOURCE_REPO, p), 4) == "\x7FELF" }
receipt["archive_tracked_bytes"] = staged.sum { |p| File.size(File.join(SOURCE_REPO, p)) }
checked("git", "-C", SOURCE_REPO, "commit", "--quiet", "-m", "Preserve four DeepSeek attempts superseded by the output-limit correction")
receipt["superseded_source_commit"] = checked("git", "-C", SOURCE_REPO, "rev-parse", "HEAD").strip
prepared.each do |path, manifest|
  manifest["runtime_amendment"]["superseded_source_commit"] = receipt.fetch("superseded_source_commit")
  write(File.join(path, "campaign.json"), manifest)
end
queue.merge!("controller_source_commit" => COMMIT, "controller_directory" => CONTROLLER, "runtime_amendment" => EVIDENCE)
write(queue_path, queue)
write(File.join(EVIDENCE, "amendment.json"), receipt)
OpenCodeCampaignQueue.new(QUEUE)
raise "Retained observation count differs" unless Dir[File.join(deepseek, "observations/*.json")].size == 109 && Dir.children(results).size == 109
puts JSON.pretty_generate(receipt.reject { |k, _| k == "superseded_file_hashes" })
puts "Prepared only; generation has not launched."
