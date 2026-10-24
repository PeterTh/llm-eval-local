# frozen_string_literal: true
require "json"
require "yaml"
require "digest"
require "fileutils"
require "open3"
require "time"
root = "/home/petert/llm_timing_audit/20261024-deepseek41-opencode-isolated"
amendment = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high/amendments/20261023-filesystem-isolation"
evidence = File.join(amendment, "evaluation")
archive = File.join(root, "citation-syntax-amendment")
raise "Citation amendment already exists" if File.exist?(archive)
missing = "cholesky_deepseek-v4.1-flash-oc-high_hybrid_r5"
results = Dir[File.join(root, "results/*.json")].sort
raise "Unexpected retained scope" unless results.size == 9 && !File.exist?(File.join(root, "results", "#{missing}.json"))
manifest_path = File.join(root, "manifest.yaml")
schema_path = File.join(root, "result-schema.json")
manifest = YAML.safe_load_file(manifest_path)
schema = JSON.parse(File.read(schema_path))
FileUtils.mkdir_p(archive)
[manifest_path, schema_path].each { |path| FileUtils.cp(path, archive) }
pattern = "^[1-9][0-9]*(-[1-9][0-9]*)?$"
raise "Schema already constrained" if schema.dig("properties", "evidence", "items", "properties", "lines").key?("pattern")
schema.fetch("properties").fetch("evidence").fetch("items").fetch("properties").fetch("lines")["pattern"] = pattern
File.write(schema_path, JSON.pretty_generate(schema) + "\n")
manifest.fetch("artifacts")["result_schema_sha256"] = Digest::SHA256.file(schema_path).hexdigest
report = { "amended_at" => Time.now.utc.iso8601, "pending_id" => missing,
  "retained_results" => results.to_h { |path| [File.basename(path), Digest::SHA256.file(path).hexdigest] },
  "original_manifest_sha256" => Digest::SHA256.file(File.join(archive, "manifest.yaml")).hexdigest,
  "original_schema_sha256" => Digest::SHA256.file(File.join(archive, "result-schema.json")).hexdigest,
  "schema_sha256" => manifest.dig("artifacts", "result_schema_sha256"),
  "change" => "Constrain each evidence.lines value to the single contiguous range already required by the unchanged result validator. The same schema pattern is already used by independent and QT reviewers. Prompt, source, model, effort, runner and scientific criteria are unchanged.",
  "retries" => "Retry only the missing Luna response. Preserve all nine accepted results and all three malformed-response attempts; no stronger-model escalation for formatting." }
manifest["citation_syntax_amendment"] = report.slice("amended_at", "pending_id", "original_manifest_sha256", "original_schema_sha256", "change")
File.write(manifest_path, YAML.dump(manifest))
[archive, evidence].each { |dir| File.write(File.join(dir, "citation-syntax-amendment.json"), JSON.pretty_generate(report) + "\n") }
FileUtils.cp(__FILE__, File.join(evidence, "retry-citation-syntax.rb"))
command = JSON.parse(File.read(File.join(amendment, "timing-handoff-launch.json"))).fetch("command")
system("systemctl", "--user", "reset-failed", "llm-deepseek41-isolated-timing-20261024.service") || raise("Reset failed")
system(*command) || raise("Retry launch failed")
puts JSON.pretty_generate(report)
