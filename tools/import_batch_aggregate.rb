#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "artifact_common"
require "optparse"

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |p|
    p.on("--native-run=PATH") { |v| options[:native] = File.expand_path(v) }
    p.on("--batch=ID") { |v| options[:batch] = v }
  end.parse!
  abort "--native-run and --batch are required" unless options[:native] && options[:batch]&.match?(/\A\d{8}-\d{6}\z/)
  root = File.expand_path("..", __dir__)
  batch = File.join(root, "batches", options.fetch(:batch))
  raise "batch has not been exported" unless File.directory?(batch)
  native = options.fetch(:native)
  metadata = LocalEvalArtifact.load_yaml(File.join(native, "aggregate_metadata.yaml"))
  {
    "manifest_sha256" => "evaluation_manifest.yaml",
    "validation_results_sha256" => "validation/all_validation_results.yaml",
    "benchmark_full_results_sha256" => "benchmark/benchmark_full_results.yaml",
    "benchmark_config_sha256" => "benchmark_config.yaml",
    "aggregate_results_sha256" => "aggregate_results.yaml",
    "source_correction_amendment_sha256" => "source_correction_amendment.yaml"
  }.each do |key, relative|
    raise "stale native aggregate #{key}" unless metadata.fetch(key) == LocalEvalArtifact.sha256(File.join(native, relative))
  end
  amendment_path = File.join(native, "pipeline_amendment.yaml")
  amendment_digest = File.file?(amendment_path) ? LocalEvalArtifact.sha256(amendment_path) : nil
  raise "stale native aggregate pipeline_amendment_sha256" unless metadata.fetch("pipeline_amendment_sha256") == amendment_digest
  csv = File.binread(File.join(native, "aggregate_results.csv"))
  rows = CSV.parse(csv, headers: true)
  summary = JSON.parse(File.read(File.join(batch, "summary.json")))
  raise "aggregate count mismatch" unless rows.size == summary.fetch("validation_records")
  raise "wrong source batch" unless rows.all? { |r| r["source_batch"] == options.fetch(:batch) }
  summary["benchmark"] = JSON.parse(File.read(File.join(batch, "benchmark/summary.json")))
  summary.fetch("timing_corrections")["benchmark_successful"] = summary.fetch("benchmark").fetch("timing_fixed_successful")
  summary["updated_at"] = metadata.fetch("generated_at")
  File.write(File.join(batch, "summary.json"), JSON.pretty_generate(summary) + "\n")
  destination = File.join(batch, "aggregate")
  # Retain only the amendment delta; unchanged pipeline files already exist in the batch.
  pipeline = if amendment_digest
    LocalEvalArtifact.load_yaml(amendment_path).fetch("amended_pipeline_source")
  else
    LocalEvalArtifact.load_yaml(File.join(native, "evaluation_manifest.yaml")).fetch("pipeline_source")
  end
  layout = pipeline.fetch("files").to_h do |relative, digest|
    stored = "method/validation/#{relative}"
    unless File.file?(File.join(batch, stored)) && LocalEvalArtifact.sha256(File.join(batch, stored)) == digest
      source = File.join(pipeline.fetch("root"), relative)
      raise "amended pipeline source changed #{relative}" unless LocalEvalArtifact.sha256(source) == digest
      stored = "benchmark/method/pipeline-delta/#{relative}"
      FileUtils.mkdir_p(File.dirname(File.join(batch, stored)))
      FileUtils.cp(source, File.join(batch, stored))
    end
    [relative, stored]
  end
  File.write(File.join(batch, "benchmark/method/pipeline-layout.json"), JSON.pretty_generate(layout) + "\n")
  FileUtils.mkdir_p(destination)
  File.binwrite(File.join(destination, "aggregate_results.csv"), csv)
  FileUtils.cp(File.join(native, "aggregate_metadata.yaml"), destination)
  FileUtils.cp(File.join(native, "aggregate_parse_warnings.yaml"), destination)
  receipt = {
    "schema_version" => 1, "native_aggregate_csv_sha256" => Digest::SHA256.hexdigest(csv),
    "native_aggregate_metadata_sha256" => LocalEvalArtifact.sha256(File.join(native, "aggregate_metadata.yaml")),
    "records" => rows.size,
    "note" => "Exact native CSV and freshness metadata retained; redundant Ruby-object YAML is retained in the native run, not replicated here."
  }
  File.write(File.join(destination, "export.json"), JSON.pretty_generate(receipt) + "\n")
  puts "Imported #{rows.size} aggregate records"
end
