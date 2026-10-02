#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "current_release"

root = File.expand_path("..", __dir__)
shared = "corrections/20261001-gpt6-qt"
catalog_path = File.join(root, "release/catalog.json")
catalog = JSON.parse(File.read(catalog_path))
raise "GPT-6 already integrated" if catalog.key?("correction_campaign")
reader = CurrentRelease.new(root)
old = catalog.fetch("campaigns").flat_map { |c| reader.load_records(c.fetch("benchmark_records")).to_a }.to_h
registry = LocalEvalArtifact.read_jsonl(File.join(root, shared, "final/corrections.jsonl"))
replacements = reader.load_records("#{shared}/benchmark/records/*/*.jsonl")
affected = replacements.keys.sort
unaffected = old.reject { |id, _| affected.include?(id) }
digest = ->(value) { Digest::SHA256.hexdigest(LocalEvalArtifact.canonical_json_for_digest(value.sort.to_h)) }
inputs = catalog.fetch("campaigns").flat_map do |c|
  %w[aggregate_csv validation_records corrected_validation_records benchmark_records benchmark_config manifest].filter_map { |key| c[key] }
end.flat_map { |pattern| Dir[File.join(root, pattern)] }.sort.to_h { |p| [LocalEvalArtifact.relative_path(root, p), LocalEvalArtifact.sha256(p)] }
guard = { "schema_version" => 1, "previous_artifact_commit" => "91472d108d477d7c2e40f0596b66cbd171d37536", "affected_ids" => affected,
  "unaffected_records" => unaffected.size, "unaffected_records_sha256" => digest.call(unaffected),
  "prior_records_sha256" => digest.call(old), "immutable_input_files" => inputs,
  "policy" => "Replace only these 32 historical QT records in the release view. Immutable source campaigns and all unrelated observations remain unchanged." }
File.write(File.join(root, shared, "release-guard.json"), JSON.pretty_generate(guard) + "\n")
histories = registry.map do |r|
  id = r.fetch("program_id")
  latest = %w[original corrected].to_h do |kind|
    [kind, { "commit" => r.dig("#{kind}_source", "commit"), "digest" => r.dig("#{kind}_source", "digest"), "url" => r.fetch("#{kind}_source_url") }]
  end
  prior = old[id]&.fetch("timing_correction")
  { "id" => id, "issue_categories" => ((prior && prior.fetch("issue_categories") || []) + r.fetch("original_issue_categories")).uniq,
    "original_source" => prior ? prior.fetch("original_source") : latest.fetch("original"),
    "intermediate_sources" => prior ? [prior.fetch("corrected_source")] : [], "corrected_source" => latest.fetch("corrected"),
    "latest_correction_baseline" => latest.fetch("original") }
end
LocalEvalArtifact.write_jsonl(File.join(root, shared, "source-history.jsonl"), histories)
raise "Intermediate source history count differs" unless histories.count { |r| !r.fetch("intermediate_sources").empty? } == 12
comparisons = affected.map do |id|
  before, after = old.fetch(id), replacements.fetch(id)
  raise "Historical status changed #{id}" unless before.fetch("success") == after.fetch("success")
  { "id" => id, "prior" => before.slice("success", "metrics", "configuration_sha256", "timing_fixed"),
    "corrected" => after.slice("success", "metrics", "configuration_sha256", "timing_fixed") }
end
LocalEvalArtifact.write_jsonl(File.join(root, shared, "rerun-comparison.jsonl"), comparisons)
catalog["generated_at"] = "2026-10-02T01:03:56Z"
catalog["expected"] = { "runs" => 5940, "models" => 27, "benchmarked" => 5076, "successful" => 4703, "timing_fixed" => 830 }
catalog["correction_campaign"] = { "root" => shared,
  "validation_records" => "#{shared}/revalidation/validation/records/*/*.jsonl", "benchmark_records" => "#{shared}/benchmark/records/*/*.jsonl",
  "source_history" => "#{shared}/source-history.jsonl", "expected" => { "corrections" => 81, "historical_benchmarks" => 32, "failed_revalidations" => 2 } }
catalog.fetch("campaigns") << { "id" => "20260929-135931", "validation_format" => "shared",
  "aggregate_csv" => "batches/20260929-135931/aggregate/aggregate_results.csv",
  "validation_records" => "batches/20260929-135931/validation/records/*/*.jsonl",
  "benchmark_records" => "batches/20260929-135931/benchmark/records/*/*.jsonl",
  "benchmark_config" => "batches/20260929-135931/benchmark/provenance/benchmark_config.yaml",
  "manifest" => "batches/20260929-135931/provenance/evaluation_manifest.yaml",
  "source_commit" => "32f1becd283322d1edff43dd47a3b3bc8e2cdad6", "corrected_source_commit" => "3a47d7cba6624f4bdfe004fba3383b5e3c62e93f",
  "exact_codex_usage" => "metadata/codex-usage/20260929-135931.jsonl",
  "generation_manifest" => "batches/20260929-135931/generation/campaign.json" }
File.write(catalog_path, JSON.pretty_generate(catalog) + "\n")
puts "Prepared exact 32-ID replacement overlay; #{unaffected.size} historical benchmark records guarded; 12 intermediate source versions retained."
