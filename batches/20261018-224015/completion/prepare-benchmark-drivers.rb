# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

scratch = __dir__
previous = "/home/petert/llm_para_campaigns/20261017-192226-sol61-opencode-medium/evaluation"
campaign = "/home/petert/llm_para_campaigns/20261018-224015-luna6-opencode-medium/evaluation"
method = File.join(scratch, "experiment")
commit = "1232f9535663243f34b34f929dc18a29d990ee65"
validation_path = File.join(campaign, "validation-completion-review.json")
audit_path = File.join(campaign, "audit-completion-review.json")
validation = JSON.parse(File.read(validation_path))
audit = JSON.parse(File.read(audit_path))
raise "Incomplete validation" unless validation.fetch("completed") == 220 && validation.fetch("infrastructure_errors").empty?
raise "Unresolved timing audit" unless audit.fetch("passed") && audit.fetch("unresolved").empty?
valid = validation.fetch("passed")
corrections = audit.fetch("verdicts").fetch("invalid", 0)
raise "Expected accepted timing corrections" unless corrections.positive? && corrections <= valid

helper = "tools/timing_audit/bin/benchmark_validation_batch.rb"
bytes, status = Open3.capture2("git", "-C", method, "show", "#{commit}:#{helper}")
raise "Cannot read pinned orchestration" unless status.success?
raise "Frozen orchestration differs" unless bytes == File.binread(File.join(method, helper))
original_sha = Digest::SHA256.hexdigest(bytes)
{
  'require_relative "../../../lib/local_evaluation"' => "require #{File.join(method, 'lib/local_evaluation').inspect}",
  'require_relative "../lib/timing_audit"' => "require #{File.join(method, 'tools/timing_audit/lib/timing_audit').inspect}"
}.each do |before, after|
  raise "Missing dependency binding" unless bytes.scan(before).size == 1
  bytes = bytes.sub(before, after)
end
orchestration = File.join(scratch, "benchmark-orchestration.rb")
raise "Orchestration already exists" if File.exist?(orchestration)
File.binwrite(orchestration, bytes)

mapping = JSON.parse(File.read(File.join(scratch, "review-template-reuse.json"))).fetch("replacements").merge(
  "llm-sol61-oc-" => "llm-luna6-oc-",
  "-20261018" => "-20261019",
  "Sol61OpenCodeBenchmarkETA" => "Luna6OpenCodeBenchmarkETA",
  "Sol 6.1 OpenCode" => "Luna 6 OpenCode",
  "a7f8f73742ee8f43391d5e9753781323eabfe8cf60f0452e98633d47e68faf23" => validation.fetch("validation_results_sha256"),
  "== 14" => "== #{corrections}",
  "Exactly 14 timing-corrected programs" => "Exactly #{corrections} timing-corrected programs",
  '"validation_failed" => 1' => "\"validation_failed\" => #{220 - valid}"
)
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
names = %w[canary-driver.rb benchmark-driver.rb verify-benchmark-records.rb benchmark-eta.rb benchmark-monitor.rb test-benchmark-eta.rb launch-measurement-stage.rb start-benchmark-monitor.rb]
records = names.map do |name|
  input = File.join(previous, name)
  output = File.join(scratch, name)
  raise "Driver already exists: #{name}" if File.exist?(output)
  original = File.binread(input)
  adapted = original.gsub(pattern) { |old| mapping.fetch(old) }.gsub(/\b219\b/, valid.to_s)
  raise "Previous campaign identity remains: #{name}" if adapted.match?(/20261017-192226|20261018-sol61-opencode|sol61-oc-|Sol61OpenCode|Sol 6\.1 OpenCode|a7f8f73742ee8f43391d5e9753781323eabfe8cf60f0452e98633d47e68faf23/)
  File.binwrite(output, adapted)
  out, err, result = Open3.capture3("ruby", "-c", output)
  raise "Syntax error: #{out}#{err}" unless result.success?
  { "file" => name, "template" => input, "template_sha256" => Digest::SHA256.hexdigest(original), "adapted_sha256" => Digest::SHA256.hexdigest(adapted) }
end
out, err, result = Open3.capture3("ruby", "-c", orchestration)
raise "Orchestration syntax error: #{out}#{err}" unless result.success?
receipt = {
  "prepared_at" => Time.now.utc.iso8601, "validation_report_sha256" => Digest::SHA256.file(validation_path).hexdigest,
  "audit_report_sha256" => Digest::SHA256.file(audit_path).hexdigest, "valid_programs" => valid, "timing_corrections" => corrections,
  "orchestration_source_commit" => commit, "orchestration_source_path" => helper,
  "orchestration_source_sha256" => original_sha, "execution_snapshot_sha256" => Digest::SHA256.file(orchestration).hexdigest,
  "snapshot_changes" => "Only two require paths rebound to the frozen native pipeline and audit helper.",
  "template_policy" => "Reuse completed Sol/OpenCode campaign drivers; only identities, paths, counts and provenance change. No recalibration or historical re-execution.",
  "replacements" => mapping, "scope_count_replacement" => { "from" => 219, "to" => valid },
  "canary_preference" => ["black-scholes"], "canary_policy" => "Lowest unchanged valid repetition in each backend, retained without repetition.",
  "native_pipeline_sha256" => validation.dig("input_revisions", "pipeline_source_sha256"),
  "drivers" => records
}
report = File.join(scratch, "benchmark-driver-template-reuse.json")
File.write(report, JSON.pretty_generate(receipt) + "\n")
(names + ["benchmark-orchestration.rb", "prepare-benchmark-drivers.rb", File.basename(report)]).each do |name|
  destination = File.join(campaign, name)
  raise "Persistent driver exists: #{name}" if File.exist?(destination)
  FileUtils.cp(File.join(scratch, name), destination)
end
puts JSON.pretty_generate(receipt)
