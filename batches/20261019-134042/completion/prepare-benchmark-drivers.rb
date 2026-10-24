# frozen_string_literal: true

require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

scratch = __dir__
previous = "/home/petert/llm_para_campaigns/20261018-224015-luna6-opencode-medium/evaluation"
campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/evaluation"
method = File.join(scratch, "experiment")
commit = "8af32415270916c4c094f1bfd61b45c9e8eb5da4"
validation_path = File.join(campaign, "validation-completion-review.json")
audit_path = File.join(campaign, "audit-completion-review.json")
validation = JSON.parse(File.read(validation_path))
audit = JSON.parse(File.read(audit_path))
raise "Incomplete validation" unless validation.fetch("completed") == 220 && validation.fetch("infrastructure_errors").empty?
raise "Unresolved timing audit" unless audit.fetch("passed") && audit.fetch("unresolved").empty?
valid = validation.fetch("passed")
corrections = audit.fetch("verdicts").fetch("invalid")
raise "Unexpected selection" unless valid == 218 && corrections == 57

helper = "tools/timing_audit/bin/benchmark_validation_batch.rb"
bytes, status = Open3.capture2("git", "-C", method, "show", "#{commit}:#{helper}")
raise "Cannot read pinned orchestration" unless status.success?
raise "Frozen orchestration differs" unless bytes == File.binread(File.join(method, helper))
original_sha = Digest::SHA256.hexdigest(bytes)
raise "Historical orchestration differs" unless original_sha == "833d5d89b8a329a7e9828c19e957ad7f8edeb39494ec6a13774402eaaca64993"
{
  'require_relative "../../../lib/local_evaluation"' => "require #{File.join(method, 'lib/local_evaluation').inspect}",
  'require_relative "../lib/timing_audit"' => "require #{File.join(method, 'tools/timing_audit/lib/timing_audit').inspect}"
}.each do |before, after|
  raise "Missing dependency binding" unless bytes.scan(before).size == 1
  bytes = bytes.sub(before, after)
end
orchestration = File.join(scratch, "benchmark-orchestration.rb")
raise "Orchestration already exists" if File.exist?(orchestration)

mapping = JSON.parse(File.read(File.join(scratch, "review-template-reuse.json"))).fetch("replacements").merge(
  "llm-luna6-oc-" => "llm-deepseek41-oc-",
  "-20261019.service" => "-20261023.service",
  "-20261019.timer" => "-20261023.timer",
  'llm-luna6-oc-benchmark-monitor-20261019"' => 'llm-deepseek41-oc-benchmark-monitor-20261023"',
  "Luna6OpenCodeBenchmarkETA" => "DeepSeek41OpenCodeBenchmarkETA",
  "Luna 6 OpenCode" => "DeepSeek V4.1 Flash OpenCode",
  "e62c715b12483ed8effb8d159ec7fea297f34d477cbef962e51f874deb12b024" => validation.fetch("validation_results_sha256"),
  '"validation_failed" => 39' => '"validation_failed" => 2'
)
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
names = %w[canary-driver.rb benchmark-driver.rb verify-benchmark-records.rb benchmark-eta.rb benchmark-monitor.rb test-benchmark-eta.rb start-benchmark-monitor.rb]
prepared = names.map do |name|
  input = File.join(previous, name)
  output = File.join(scratch, name)
  raise "Driver already exists: #{name}" if File.exist?(output)
  original = File.binread(input)
  adapted = original.gsub(pattern) { |old| mapping.fetch(old) }.gsub(/\b181\b/, valid.to_s)
  raise "Previous campaign identity remains: #{name}" if adapted.match?(/20261018-224015|20261019-luna6-opencode|luna6-oc-|Luna6OpenCode|Luna 6 OpenCode|e62c715b12483ed8effb8d159ec7fea297f34d477cbef962e51f874deb12b024/)
  [name, input, original, adapted]
end
File.binwrite(orchestration, bytes)
records = prepared.map do |name, input, original, adapted|
  output = File.join(scratch, name)
  File.binwrite(output, adapted)
  out, err, result = Open3.capture3("ruby", "-c", output)
  raise "Syntax error: #{out}#{err}" unless result.success?
  { "file" => name, "template" => input, "template_sha256" => Digest::SHA256.hexdigest(original), "adapted_sha256" => Digest::SHA256.hexdigest(adapted) }
end
out, err, result = Open3.capture3("ruby", "-c", orchestration)
raise "Orchestration syntax error: #{out}#{err}" unless result.success?
launcher = File.join(scratch, "launch-measurement-stage.rb")
raise "Prepared stage launcher changed" unless File.binread(launcher) == File.binread(File.join(campaign, File.basename(launcher)))
receipt = {
  "prepared_at" => Time.now.utc.iso8601,
  "validation_report_sha256" => Digest::SHA256.file(validation_path).hexdigest,
  "audit_report_sha256" => Digest::SHA256.file(audit_path).hexdigest,
  "valid_programs" => valid, "timing_corrections" => corrections,
  "orchestration_source_commit" => commit, "orchestration_source_path" => helper,
  "orchestration_source_sha256" => original_sha,
  "execution_snapshot_sha256" => Digest::SHA256.file(orchestration).hexdigest,
  "snapshot_changes" => "Only two require paths rebound to the frozen native pipeline and audit helper.",
  "template_policy" => "Reuse completed Luna/OpenCode campaign drivers; only identities, paths, counts and provenance change. No recalibration or historical re-execution.",
  "replacements" => mapping, "scope_count_replacement" => { "from" => 181, "to" => valid },
  "canary_preference" => ["black-scholes"],
  "canary_policy" => "Lowest unchanged valid repetition in each backend, retained without repetition.",
  "native_pipeline_sha256" => validation.dig("input_revisions", "pipeline_source_sha256"),
  "previously_prepared_launcher_sha256" => Digest::SHA256.file(launcher).hexdigest,
  "drivers" => records
}
report = File.join(scratch, "benchmark-driver-template-reuse.json")
File.write(report, JSON.pretty_generate(receipt) + "\n")
(names + ["benchmark-orchestration.rb", "prepare-benchmark-drivers.rb", File.basename(report)]).each do |name|
  destination = File.join(campaign, name)
  raise "Persistent driver exists: #{name}" if File.exist?(destination)
  FileUtils.cp(File.join(scratch, name), destination)
end
puts JSON.pretty_generate(receipt.except("replacements"))
