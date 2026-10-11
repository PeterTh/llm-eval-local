require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

root = "/home/petert/llm_para_campaigns/20261006-204623-sol61-medium-xhigh"
batch = "/home/petert/llm_para_experiments/20261006-204623"
id = "floydwarshall_gpt-6.1-sol-xhigh_cuda_r2"
source = File.join(batch, id)
destination = File.join(root, "failed-attempts", id, "attempt-001")
raise "An accepted observation must not be retried" if File.exist?(File.join(root, "observations", "#{id}.json"))
raise "Archive already exists" if File.exist?(destination)
pids, state = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is busy" unless state.exitstatus == 1 && pids.empty?
process = JSON.parse(File.read(File.join(source, "process-status.txt")))
transcript = File.read(File.join(source, "output.txt"))
timing = File.read(File.join(source, "timing.txt"))
raise "Not the inspected capacity failure" unless process["exit_status"] == 1 && process["term_signal"].nil? &&
  process["timeout_seconds"] == 14400 && transcript.lines.grep(/^ERROR:/).map(&:strip).uniq ==
    ["ERROR: Selected model is at capacity. Please try a different model."] &&
  transcript.include?("model: gpt-6.1-sol\n") && transcript.include?("reasoning effort: xhigh\n") &&
  timing.include?("Duration: 103.57 seconds")
reports = Dir[File.join(root, "observations", "*.json")].sort
raise "Completed scope changed" unless reports.size == 124
hashes = Dir[File.join(source, "**", "*"), File.join(source, "**", ".*")].uniq.sort.select { |p| File.file?(p) }.to_h do |path|
  [path.delete_prefix(source + "/"), Digest::SHA256.file(path).hexdigest]
end
FileUtils.mkdir_p(destination)
%w[progress.json monitor-status.json].each { |name| FileUtils.cp(File.join(root, name), File.join(destination, name)) }
FileUtils.cp(File.join(root, "cleanup", "#{id}.json"), File.join(destination, "cleanup.json"))
FileUtils.mv(source, File.join(destination, "output"))
hashes.each do |relative, digest|
  raise "Archive mismatch: #{relative}" unless Digest::SHA256.file(File.join(destination, "output", relative)).hexdigest == digest
end
receipt = { "recorded_at" => Time.now.utc.iso8601, "campaign_id" => "20261006-204623", "id" => id,
  "reason" => "Provider capacity error, not a model/program outcome or production-budget timeout",
  "decision" => "Preserve attempt outside the canonical batch and retry this ID only with unchanged frozen inputs, model, effort and budget",
  "archive" => File.join(destination, "output"), "excluded_failed_attempt_seconds" => 103.57,
  "completed_observations_preserved" => reports.size, "retry_performed" => false,
  "sha256" => hashes, "accepted_observation_sha256" => reports.to_h { |p| [File.basename(p), Digest::SHA256.file(p).hexdigest] } }
File.write(File.join(destination, "recovery.json"), JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, File.join(destination, File.basename(__FILE__)))
puts JSON.generate(receipt.slice("id", "archive", "excluded_failed_attempt_seconds", "completed_observations_preserved", "retry_performed"))
