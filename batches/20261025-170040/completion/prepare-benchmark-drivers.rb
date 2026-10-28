# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

scratch = __dir__
previous = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/evaluation"
campaign = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation"
method = File.join(scratch, "experiment")
commit = "cd193c22bfefcb1ac0d12f43a0ec018ac7fcad88"
validation_path = File.join(campaign, "validation-completion-review.json")
audit_path = File.join(campaign, "audit-completion-review.json")
validation = JSON.parse(File.read(validation_path))
audit = JSON.parse(File.read(audit_path))
raise "Incomplete validation" unless validation.fetch("completed") == 220 && validation.fetch("infrastructure_errors").empty?
raise "Unresolved timing audit" unless audit.fetch("passed") && audit.fetch("unresolved").empty?
valid = validation.fetch("passed")
corrections = audit.fetch("verdicts").fetch("invalid", 0)
raise "Invalid correction count" unless corrections.positive? && corrections <= valid

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
mapping = JSON.parse(File.read(File.join(scratch, "review-template-reuse.json"))).fetch("mapping").merge(
  "llm-deepseek41-oc-" => "llm-haiku55-oc-",
  "-20261023.service" => "-20261028.service",
  "-20261023.timer" => "-20261028.timer",
  'llm-deepseek41-oc-benchmark-monitor-20261023"' => 'llm-haiku55-oc-benchmark-monitor-20261028"',
  "DeepSeek41OpenCodeBenchmarkETA" => "Haiku55OpenCodeBenchmarkETA",
  "DeepSeek V4.1 Flash OpenCode" => "Haiku 5.5 OpenCode",
  "70859cb21966d3e7d8bcc6440600656d3c4beddc274e685e4fe2479c479b867e" => validation.fetch("validation_results_sha256"),
  '"validation_failed" => 2' => "\"validation_failed\" => #{220 - valid}"
)
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
names = %w[canary-driver.rb benchmark-driver.rb verify-benchmark-records.rb benchmark-eta.rb benchmark-monitor.rb test-benchmark-eta.rb start-benchmark-monitor.rb]
prepared = names.map do |name|
  input = File.join(previous, name)
  output = File.join(scratch, name)
  raise "Driver already exists: #{name}" if File.exist?(output)
  original = File.binread(input)
  adapted = original.gsub(pattern) { |old| mapping.fetch(old) }.gsub(/\b218\b/, valid.to_s)
  raise "Previous campaign identity remains: #{name}" if adapted.match?(/20261019-134042|20261023-deepseek41-opencode|deepseek41-oc-|DeepSeek41OpenCode|DeepSeek V4.1 Flash OpenCode|70859cb21966d3e7d8bcc6440600656d3c4beddc274e685e4fe2479c479b867e/)
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
receipt = {
  "prepared_at" => Time.now.utc.iso8601,
  "validation_report_sha256" => Digest::SHA256.file(validation_path).hexdigest,
  "audit_report_sha256" => Digest::SHA256.file(audit_path).hexdigest,
  "valid_programs" => valid, "timing_corrections" => corrections,
  "orchestration_source_commit" => commit, "orchestration_source_path" => helper,
  "orchestration_source_sha256" => original_sha,
  "execution_snapshot_sha256" => Digest::SHA256.file(orchestration).hexdigest,
  "snapshot_changes" => "Only two require paths rebound to the frozen native pipeline and audit helper.",
  "template_policy" => "Reuse completed DeepSeek/OpenCode campaign drivers; only identities, paths, counts and provenance change. No recalibration or historical re-execution.",
  "replacements" => mapping, "scope_count_replacement" => { "from" => 218, "to" => valid },
  "canary_preference" => ["black-scholes"],
  "canary_policy" => "Lowest unchanged valid repetition in each backend, retained without repetition.",
  "native_pipeline_sha256" => validation.dig("input_revisions", "pipeline_source_sha256"),
  "previously_prepared_launcher_sha256" => Digest::SHA256.file(launcher).hexdigest,
  "drivers" => records
}
report = File.join(scratch, "benchmark-driver-template-reuse.json")
File.write(report, JSON.pretty_generate(receipt) + "\n")
(names + ["benchmark-orchestration.rb", "prepare-benchmark-drivers.rb", File.basename(report), File.basename(launcher)]).each do |name|
  destination = File.join(campaign, name)
  if File.exist?(destination)
    raise "Persistent driver differs: #{name}" unless File.binread(destination) == File.binread(File.join(scratch, name))
  else
    FileUtils.cp(File.join(scratch, name), destination)
  end
end
puts JSON.pretty_generate(receipt.except("replacements"))
