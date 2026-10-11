require "json"
require "digest"
require "time"

root = "/home/petert/llm_para_campaigns/20261006-204623-sol61-medium-xhigh"
id = "floydwarshall_gpt-6.1-sol-xhigh_cuda_r2"
archive = File.join(root, "failed-attempts", id, "attempt-001")
initial = JSON.parse(File.read(File.join(archive, "recovery.json")))
initial.fetch("accepted_observation_sha256").each do |name, digest|
  raise "Accepted observation changed: #{name}" unless Digest::SHA256.file(File.join(root, "observations", name)).hexdigest == digest
end
replacement = JSON.parse(File.read(File.join(root, "observations", "#{id}.json")))
raise "Retry did not complete" unless replacement.fetch("outcome") == "completed"
report = { "confirmed_at" => Time.now.utc.iso8601, "id" => id, "retry_completed" => true,
  "previous_observations_verified_unchanged" => initial.fetch("accepted_observation_sha256").size,
  "replacement" => replacement.slice("session_id", "raw_total_seconds", "model", "reasoning_effort", "version", "sha256"),
  "failed_attempt_seconds_excluded" => initial.fetch("excluded_failed_attempt_seconds") }
path = File.join(archive, "retry-completed.json")
raise "Completion receipt already exists" if File.exist?(path)
File.write(path, JSON.pretty_generate(report) + "\n")
puts JSON.generate(report.reject { |key, _| key == "replacement" })
