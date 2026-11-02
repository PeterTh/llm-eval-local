# frozen_string_literal: true
require "json"
require "yaml"
require "digest"
require "fileutils"
require "open3"
require "time"
require_relative "experiment/tools/timing_audit/lib/timing_audit"

root = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
evidence = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
archive = File.join(root, "citation-syntax-amendment")
raise "Citation amendment already exists" if File.exist?(archive)
id = "stencil3d_beam-1.0-oc-medium_mpi_r5"
attempt = File.join(root, "logs", id, "attempt-04")
metadata_path = File.join(attempt, "metadata.yaml")
metadata = YAML.safe_load_file(metadata_path)
raise "Unexpected failed review" unless metadata.fetch("exit_code") == 0 && !metadata["result_sha256"] && metadata["usage"]
raise "Review attempt changed" unless metadata.fetch("events_sha256") == "8de1f8df9b3aefc0fb7047fb7c63542af03bebb972482517aa5a8c1c348566dd"
events_path = File.join(attempt, "events.jsonl")
raise "Events changed" unless TimingAudit.sha256_file(events_path) == metadata.fetch("events_sha256")
TimingAudit.verify_static_events!(events_path)
events = File.readlines(events_path).map { |line| JSON.parse(line) }
output = events.filter_map { |event| event.dig("item", "text") if event.dig("item", "type") == "agent_message" }.last
candidate = JSON.parse(output)
raise "Unexpected formatting defect" unless candidate.fetch("evidence").any? { |item| item.fetch("lines") == "175-179, 194-223" }
records = TimingAudit.load_jsonl(File.join(root, "inventory.jsonl"))
begin
  TimingAudit::ResultValidator.new(records).validate!(candidate, expected_id: id)
  raise "Candidate unexpectedly valid"
rescue RuntimeError => error
  raise unless error.message == "Invalid evidence line range"
end
results = Dir[File.join(root, "results/*.json")].sort
raise "Retained scope differs" unless results.size == 8 && !File.exist?(File.join(root, "results", id + ".json"))
verifier = TimingAudit::AuditVerifier.new(root, "trial")
results.each { |path| verifier.verify_result!(File.basename(path, ".json"), JSON.parse(File.read(path))) }
unit = "llm-beam10-oc-timing-pilot-paced-20261030.service"
state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
raise "Paced review is still active" unless status.success? && %w[inactive failed].include?(state.strip)
raise "Minimum request spacing has not elapsed" unless Time.now >= Time.iso8601(metadata.fetch("started_at")) + 90
raise "Too late before Fable reset" unless Time.now + 930 < Time.iso8601("2026-10-30T17:00:00Z")
manifest_path = File.join(root, "manifest.yaml")
schema_path = File.join(root, "result-schema.json")
manifest = YAML.safe_load_file(manifest_path)
schema = JSON.parse(File.read(schema_path))
raise "Schema already constrained" if schema.dig("properties", "evidence", "items", "properties", "lines").key?("pattern")
FileUtils.mkdir_p(archive)
[manifest_path, schema_path].each { |path| FileUtils.cp(path, archive) }
schema.fetch("properties").fetch("evidence").fetch("items").fetch("properties").fetch("lines")["pattern"] = "^[1-9][0-9]*(-[1-9][0-9]*)?$"
File.write(schema_path, JSON.pretty_generate(schema) + "\n")
manifest.fetch("artifacts")["result_schema_sha256"] = TimingAudit.sha256_file(schema_path)
log = File.join(evidence, "audit-pilot-paced-driver.log")
report = { "amended_at" => Time.now.utc.iso8601, "pending_id" => id,
  "retained_results" => results.to_h { |path| [path, TimingAudit.sha256_file(path)] },
  "formatting_attempt" => { "metadata_path" => metadata_path, "metadata_sha256" => TimingAudit.sha256_file(metadata_path), "events_sha256" => metadata.fetch("events_sha256") },
  "original_manifest_sha256" => TimingAudit.sha256_file(File.join(archive, "manifest.yaml")),
  "original_schema_sha256" => TimingAudit.sha256_file(File.join(archive, "result-schema.json")),
  "schema_sha256" => manifest.dig("artifacts", "result_schema_sha256"),
  "prior_paced_log_sha256" => TimingAudit.sha256_file(log), "prior_paced_log_bytes" => File.size(log),
  "change" => "Reuse the DeepSeek citation-format amendment: constrain evidence.lines to the one contiguous range already required by the unchanged validator. Prompt, source, model, effort, tool restrictions and scientific criteria unchanged. No manual alteration of review verdicts.",
  "retry_policy" => "Keep all eight accepted reviews and all failed attempts. Resume only missing requests through the unchanged paced driver. No generated program or native measurement rerun." }
manifest["citation_syntax_amendment"] = report.slice("amended_at", "pending_id", "original_manifest_sha256", "original_schema_sha256", "change")
File.write(manifest_path, YAML.dump(manifest))
[archive, evidence].each { |dir| File.write(File.join(dir, "audit-pilot-citation-recovery.json"), JSON.pretty_generate(report) + "\n", mode: "wx") }
FileUtils.cp(__FILE__, evidence)
driver = File.join(__dir__, "paced-audit-driver.rb")
receipt = JSON.parse(File.read(File.join(evidence, "audit-pilot-paced-launch.json")))
receipt.fetch("files").each { |path, sha| raise "Paced method changed" unless TimingAudit.sha256_file(path) == sha }
raise "Recovery launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Beam static timing pilot with existing citation-format constraint",
  "--property=WorkingDirectory=#{__dir__}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}",
  "/usr/bin/ruby", driver, "pilot")
current, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "MainPID", "-p", "InvocationID")
raise "Cannot inspect recovered pilot" unless status.success?
properties = current.lines.to_h { |line| line.chomp.split("=", 2) }
raise "Recovered pilot not active" unless properties.fetch("ActiveState") == "active"
activation = { "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties,
  "citation_recovery_sha256" => TimingAudit.sha256_file(File.join(evidence, "audit-pilot-citation-recovery.json")),
  "paced_driver_unchanged" => true, "accepted_reviews_retained" => results.size }
File.write(File.join(evidence, "audit-pilot-citation-activation.json"), JSON.pretty_generate(activation) + "\n", mode: "wx")
puts JSON.pretty_generate(activation)
