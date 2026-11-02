# frozen_string_literal: true
require "json"
require "digest"
require "open3"
require "fileutils"
require "time"
require_relative "verified-external-validation"

scratch = __dir__
previous = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation"
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
method = File.join(scratch, "experiment")
new_method = File.join(scratch, "experiment-benchmark")
commit = "e0a06323e304b4a9c0bad2e8f5c095f3635302cc"
external = BeamExternalValidation.verify!
validation_path = File.join(campaign, "validation-completion-review.json")
audit_path = File.join(campaign, "audit-completion-supplemental-review.json")
validation = JSON.parse(File.read(validation_path))
audit = JSON.parse(File.read(audit_path))
raise "Incomplete validation" unless validation.fetch("completed") == 220 && validation.fetch("infrastructure_errors").empty?
raise "Unresolved timing audit" unless audit.fetch("passed") && audit.fetch("unresolved").empty?
valid = external.fetch(:eligible_ids).size
corrections = audit.fetch("verdicts").fetch("invalid", 0) - external.fetch(:excluded).size
raise "Invalid correction count" unless corrections.positive? && corrections <= valid

helper = "tools/timing_audit/bin/benchmark_validation_batch.rb"
bytes, status = Open3.capture2("git", "-C", new_method, "show", "#{commit}:#{helper}")
raise "Cannot read pinned orchestration" unless status.success?
raise "Frozen orchestration differs" unless bytes == File.binread(File.join(new_method, helper))
original_sha = Digest::SHA256.hexdigest(bytes)
raise "Historical orchestration differs" unless Digest::SHA256.file(File.join(method, helper)).hexdigest == "833d5d89b8a329a7e9828c19e957ad7f8edeb39494ec6a13774402eaaca64993"
{
  'require_relative "../../../lib/local_evaluation"' => "require #{File.join(method, 'lib/local_evaluation').inspect}",
  'require_relative "../lib/timing_audit"' => "require #{File.join(method, 'tools/timing_audit/lib/timing_audit').inspect}",
  'require_relative "../lib/external_validation_exclusions"' => "require #{File.join(new_method, 'tools/timing_audit/lib/external_validation_exclusions').inspect}"
}.each do |before, after|
  raise "Missing dependency binding" unless bytes.scan(before).size == 1
  bytes = bytes.sub(before, after)
end
orchestration = File.join(scratch, "benchmark-orchestration.rb")
raise "Orchestration already exists" if File.exist?(orchestration)
mapping = JSON.parse(File.read(File.join(scratch, "review-template-reuse.json"))).fetch("mapping").merge(
  "audit-completion-review.json" => "audit-completion-supplemental-review.json",
  "llm-haiku55-oc-" => "llm-beam10-oc-",
  "-20261028.service" => "-20261030.service",
  "-20261028.timer" => "-20261030.timer",
  'llm-haiku55-oc-benchmark-monitor-20261028"' => 'llm-beam10-oc-benchmark-monitor-20261030"',
  "Haiku55OpenCodeBenchmarkETA" => "Beam10OpenCodeBenchmarkETA",
  "Haiku 5.5 OpenCode" => "Beam 1.0 OpenCode",
  "1ca68d0d8db8d6b85000c4d540489bd5cb9aea29633bcee596830eb069037949" => validation.fetch("validation_results_sha256"),
  '"validation_failed" => 1' => "\"validation_failed\" => #{220 - valid}"
)
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
names = %w[canary-driver.rb benchmark-driver.rb verify-benchmark-records.rb benchmark-eta.rb benchmark-monitor.rb test-benchmark-eta.rb start-benchmark-monitor.rb]
prepared = names.map do |name|
  input = File.join(previous, name)
  output = File.join(scratch, name)
  raise "Driver already exists: #{name}" if File.exist?(output)
  original = File.binread(input)
  adapted = original.gsub(pattern) { |old| mapping.fetch(old) }.gsub(/\b219\b/, valid.to_s)
  if name == "canary-driver.rb"
    adapted = adapted.sub('canary_model: "beam-1.0-oc-medium")', "canary_model: \"beam-1.0-oc-medium\", external_validation_exclusions: #{BeamExternalValidation::REGISTRY.inspect})")
    raise "Missing canary exclusion hook" unless adapted.include?("external_validation_exclusions:")
    adapted = adapted.sub('phase = "prepare_inherited_configuration"', "require_relative \"verify-revalidation-boundary\"\n  BeamRevalidationBoundary.verify!\n  phase = \"prepare_inherited_configuration\"")
  elsif name == "verify-benchmark-records.rb"
    adapted = adapted.sub('plan.fetch("excluded_validation_ids").empty?', "plan.fetch(\"excluded_validation_ids\") == #{external.fetch(:excluded).inspect}")
    adapted = adapted.sub('.map { |row| row.fetch("program_id") },', ".map { |row| row.fetch(\"program_id\") }.concat(#{external.fetch(:excluded).inspect}).sort,")
  end
  raise "Previous campaign identity remains: #{name}" if adapted.match?(/20261025-170040|20261028-haiku55-opencode|haiku55-oc-|Haiku55OpenCode|Haiku 5.5 OpenCode|1ca68d0d8db8d6b85000c4d540489bd5cb9aea29633bcee596830eb069037949/)
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
  "snapshot_changes" => "New tested source-pinned external-validation eligibility guard; three dependency paths bind the unchanged native measurement pipeline and the new verifier. No measurement settings or execution logic changes.",
  "external_evidence_sha256" => external.fetch(:paths),
  "template_policy" => "Reuse completed Haiku/OpenCode drivers with explicit external-validation exclusions and corrected-source supplemental gate. No recalibration or historical re-execution.",
  "replacements" => mapping, "scope_count_replacement" => { "from" => 219, "to" => valid },
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
