# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

repo = "/home/petert/llm_eval/experiment"
root = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium"
incident = File.join(root, "incidents/20261029-prompt-rendering-failure")
review_path = File.join(incident, "review.json")
review = JSON.parse(File.read(review_path))
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
id = "matmul_beam-1.0-oc-medium_mpi_r3"
source = File.join(manifest.fetch("persistent_results"), id)
commit = "701061cab3da4f00527aed3df5c498041ae80ce7"
raise "Wrong incident" unless review.values_at("id", "status") == [id, "awaiting_user_adjudication"]
raise "Already adjudicated" if File.exist?(File.join(incident, "decision.json"))
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account busy" unless status.exitstatus == 1 && pids.empty?
raise "Missing operator hold" unless File.read(File.join(root, "STOP")).start_with?("Held pending user adjudication of Beam prompt-rendering failure")
log = "/tmp/beam-protocol-retention-regression-host-20261030.log"
counts = File.read(log).scan(/^(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips$/).last&.map(&:to_i)
raise "Full regression suite did not pass" unless counts == [338, 1932, 0, 0, 0]
review.fetch("accepted_observation_sha256").each do |name, sha|
  raise "Accepted observation changed" unless Digest::SHA256.file(File.join(root, "observations", name)).hexdigest == sha
end
review.fetch("affected_output_sha256").each do |name, sha|
  raise "Original attempt changed" unless Digest::SHA256.file(File.join(source, name)).hexdigest == sha
end
manifest.fetch("files").each do |name, sha|
  raise "Frozen generation method changed: #{name}" unless Digest::SHA256.file(File.join(manifest.fetch("working_directory"), name)).hexdigest == sha
  raise "Admission snapshot baseline changed: #{name}" unless Digest::SHA256.file(File.join(__dir__, name)).hexdigest == sha
end
replaced = %w[lib/opencode_generation_termination.rb lib/opencode_generation_observation.rb tools/generation_campaign.rb]
overlay = replaced.to_h do |name|
  content, err, status = Open3.capture3("git", "-C", repo, "show", "#{commit}:#{name}")
  raise err unless status.success?
  raise "Canonical committed method differs" unless File.binread(File.join(repo, name)) == content
  FileUtils.cp(File.join(repo, name), File.join(__dir__, name))
  [name, { "before" => manifest.fetch("files").fetch(name), "after" => Digest::SHA256.hexdigest(content) }]
end
decision = {
  "recorded_at" => Time.now.utc.iso8601, "id" => id, "classification" => "model_protocol_failure",
  "approved_by" => "user", "user_instruction" => "Yes, continue that way.",
  "decision" => "retain_original_without_restart", "rerun_performed" => false,
  "scientific_validation" => "Validate the original generated program normally; generation termination is not itself a validation failure.",
  "accounting" => "Preserve exact counters from completed requests as partial; do not claim a complete task cost or exclude model-failure time.",
  "protocol_tool_part_id" => "prt_18703c5ac001CbpV7YziDrY1H5",
  "review_sha256" => Digest::SHA256.file(review_path).hexdigest,
  "original_files_sha256" => review.fetch("affected_output_sha256"), "admission_method_commit" => commit
}
File.write(File.join(incident, "decision.json"), JSON.pretty_generate(decision) + "\n", mode: "wx")
tool = File.join(repo, "tools/metadata/retain_opencode_protocol_failure.rb")
output, err, status = Open3.capture3("ruby", tool, "--approved-model-failure", source, File.join(incident, "decision.json"))
raise "Adjudication failed: #{err}" unless status.success?
report = JSON.parse(output)
raise "Unexpected retained counters" unless report.values_at("raw_total_seconds", "total_seconds", "total_tokens", "usage_complete") == [34.33, 34.33, 72920, false]
File.write(File.join(incident, "retained-observation.json"), JSON.pretty_generate(report) + "\n", mode: "wx")
require File.join(__dir__, "tools/generation_campaign")
driver = GenerationCampaign.new(root)
baseline = JSON.parse(File.read(File.join(root, "preflight-gate.json"))).fetch("preflights").first
existing = review.fetch("accepted_observation_sha256").keys
existing.each { |name| driver.observation(File.basename(name, ".json"), baseline: baseline) }
raise "Retained report differs" unless driver.observation(id, baseline: baseline) == report
review.fetch("accepted_observation_sha256").each do |name, sha|
  raise "Accepted observation changed" unless Digest::SHA256.file(File.join(root, "observations", name)).hexdigest == sha
end
review.fetch("affected_output_sha256").each do |name, sha|
  raise "Original output changed" unless Digest::SHA256.file(File.join(source, name)).hexdigest == sha
end
amendment = {
  "recorded_at" => Time.now.utc.iso8601, "admission_source_commit" => commit,
  "generation_source_commit" => manifest.fetch("source_commit"), "admission_directory" => __dir__,
  "replaced_admission_files" => overlay, "generation_runtime_modified" => false,
  "generation_config_modified" => false, "original_files_unchanged" => review.fetch("affected_output_sha256").size,
  "accepted_observations_unchanged" => existing.size, "retained_observations" => existing.size + 1,
  "termination_receipt_sha256" => report.fetch("termination_record_sha256"),
  "tests" => %w[runs assertions failures errors skips].zip(counts).to_h,
  "regression_log_sha256" => Digest::SHA256.file(log).hexdigest,
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest
}
File.write(File.join(incident, "admission-amendment.json"), JSON.pretty_generate(amendment) + "\n", mode: "wx")
FileUtils.cp(log, File.join(incident, "regression-tests.log"))
FileUtils.cp(__FILE__, File.join(incident, File.basename(__FILE__)))
FileUtils.cp(tool, File.join(incident, File.basename(tool)))
driver.snapshot("adjudicated_awaiting_resume")
puts JSON.pretty_generate(amendment)
