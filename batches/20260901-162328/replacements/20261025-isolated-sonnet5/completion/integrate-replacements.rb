# frozen_string_literal: true
require_relative "release/tools/current_release"
require "open3"
require "time"

root = File.join(__dir__, "release")
evidence = "/home/petert/llm_para_campaigns/20261025-143725-sonnet5-isolated-replacements/evaluation"
batch = "20260901-162328"
baseline = "1f8de8a09767c6fd9cc77c7313d4ec0378e159b7"
receipt = JSON.parse(File.read(File.join(evidence, "batch-export.json")))
raise "Unexpected export" unless receipt.values_at("records", "benchmarks", "corrections") == [7, 6, 2]
base = receipt.fetch("evidence_root")
catalog_path = File.join(root, "release/catalog.json")
previous_catalog = File.binread(catalog_path)
catalog = JSON.parse(previous_catalog)
replacements = catalog.fetch("observation_replacements")
raise "Sonnet replacements already integrated" if replacements.any? { |r| r.fetch("id") == batch }
raise "Unexpected prior replacement scope" unless replacements.map { |r| r.fetch("id") } == ["20261019-134042"]
generation = JSON.parse(File.read(File.join(File.dirname(evidence), "campaign.json")))
ids = File.readlines(File.join(File.dirname(evidence), "run-ids.txt"), chomp: true).reject(&:empty?).sort
raise "Unexpected replacement IDs" unless ids.size == 7
reader = CurrentRelease.new(root)
prior = catalog.fetch("campaigns").find { |r| r.fetch("id") == batch }
old_rows = CSV.read(reader.path(prior.fetch("aggregate_csv")), headers: true).map(&:to_h)
validations = reader.load_records(prior.fetch("validation_records")).merge(reader.load_records(prior.fetch("corrected_validation_records")))
records = reader.load_records(prior.fetch("benchmark_records"))
# The release applies the earlier shared QT corrections before replacement
# overlays. Bind exactly that effective baseline, not the older raw CSV.
shared = SharedCorrections.new(root, catalog.fetch("correction_campaign"))
shared.apply!(validations, records, old_rows)
before = { "rows" => old_rows.to_h { |r| [CurrentRelease.id(r), r] }, "validations" => validations, "benchmarks" => records }
unaffected = before.transform_values { |data| data.reject { |id, _| ids.include?(id) } }
raise "Retained scope differs" unless before.fetch("rows").size == 660 && unaffected.fetch("rows").size == 653
guard = { "schema_version" => 1, "batch" => batch, "ids" => ids, "unaffected_observations" => 653,
  "prior_sha256" => ObservationReplacements.digest(before), "unaffected_sha256" => ObservationReplacements.digest(unaffected),
  "digest_algorithm" => LocalEvalArtifact::CANONICAL_JSON_DIGEST_ALGORITHM,
  "generation_completion_sha256" => LocalEvalArtifact.sha256(File.join(File.dirname(evidence), "completion.json")) }
File.write(File.join(root, base, "release-guard.json"), JSON.pretty_generate(guard) + "\n")
replacement = {
  "id" => batch, "evidence_root" => base, "ids" => ids, "validation_format" => "batch",
  "aggregate_csv" => "#{base}/aggregate/aggregate_results.csv", "validation_records" => "#{base}/validation/records.jsonl",
  "corrected_validation_records" => "#{base}/timing-corrections/revalidation/validation/records.jsonl",
  "benchmark_records" => "#{base}/benchmark/records/*/*.jsonl", "benchmark_config" => "#{base}/benchmark/provenance/benchmark_config.yaml",
  "manifest" => "#{base}/provenance/evaluation_manifest.yaml", "source_commit" => receipt.fetch("source_commit"),
  "corrected_source_commit" => receipt.fetch("corrected_source_commit"), "generation_harness" => "claude",
  "generation_manifest" => "#{base}/generation/campaign.json", "generation_method_layout" => "#{base}/generation/method-layout.json"
}
counts = catalog.fetch("expected")
counts["benchmarked"] += receipt.fetch("benchmarks") - ids.count { |id| records.key?(id) }
counts["successful"] += receipt.fetch("successful") - ids.count { |id| records[id]&.fetch("success") }
counts["timing_fixed"] += receipt.fetch("corrections") - ids.count { |id| before.fetch("rows").fetch(id).fetch("timing_fixed") == "true" }
catalog["generated_at"] = JSON.parse(File.read(File.join(evidence, "benchmark-completion-review.json"))).fetch("completed_at")
replacements << replacement
File.write(catalog_path, JSON.pretty_generate(catalog) + "\n")
begin
  CurrentRelease.new(root).run
rescue StandardError
  File.binwrite(catalog_path, previous_catalog)
  raise
end
old_csv, error, status = Open3.capture3("git", "-C", root, "show", "#{baseline}:release/scored_results.csv")
raise "Missing published baseline: #{error}" unless status.success?
old = CSV.parse(old_csv, headers: true).to_h { |r| [CurrentRelease.id(r), r.to_h] }
rows = CSV.read(File.join(root, "release/scored_results.csv"), headers: true).map(&:to_h)
current = rows.to_h { |r| [CurrentRelease.id(r), r] }
raise "Release ID scope changed" unless old.size == 7700 && current.keys.sort == old.keys.sort
unrelated = old.keys - ids
unrelated.each do |id|
  raise "Unrelated observation changed: #{id}" unless old.fetch(id).except("overall_score") == current.fetch(id).slice(*old.fetch(id).keys).except("overall_score")
end
generation.fetch("excluded_gpt56_ids").each do |id|
  raise "GPT-5.6 observation replaced" unless unrelated.include?(id)
end
groups = ->(values) { values.select { |r| r["benchmark_success"] == "true" }.group_by { |r| r.values_at("benchmark", "par_type").join("/") }.transform_values { |rs| rs.sort_by { |r| [Float(r.fetch("benchmark_median_time")), CurrentRelease.id(r)] } } }
prior_groups, current_groups = groups.call(old.values), groups.call(rows)
new_winners = current_groups.filter_map do |cell, entries|
  winner, previous = CurrentRelease.id(entries.first), CurrentRelease.id(prior_groups.fetch(cell).first)
  next if winner == previous
  raise "Winner changed outside replacement scope" unless ids.include?(winner)
  { "cell" => cell, "winner" => winner, "median_ms" => Float(entries.first.fetch("benchmark_median_time")),
    "previous" => previous, "previous_median_ms" => Float(prior_groups.fetch(cell).first.fetch("benchmark_median_time")),
    "top" => entries.first(8) }
end
context = { "schema_version" => 1, "date" => "2026-10-25", "baseline_commit" => baseline,
  "baseline_scored_csv_sha256" => Digest::SHA256.hexdigest(old_csv), "replacement_ids" => ids,
  "unchanged_other_observations" => unrelated.size, "untouched_audited_gpt56_ids" => generation.fetch("excluded_gpt56_ids"),
  "new_winners" => new_winners, "before" => old.slice(*ids), "after" => current.slice(*ids),
  "source_commits" => receipt.slice("source_commit", "corrected_source_commit"),
  "policy" => "Replace exactly seven observations. Retain the ordinary numerical validation failure, accepted timing-only corrections and original Git revisions. No unrelated reruns." }
context_path = "analysis/notes/2026-10-25-sonnet5-replacement-context.json"
File.write(File.join(root, context_path), JSON.pretty_generate(context) + "\n")
report = { "integrated_at" => Time.now.utc.iso8601, "counts" => counts, "baseline_commit" => baseline,
  "unrelated_observations_unchanged" => unrelated.size, "unaffected_claude5_observations" => 653,
  "gpt56_observations_replaced" => 0, "new_winners" => new_winners.map { |r| r.fetch("winner") },
  "prior_programs_rescored" => unrelated.count { |id| old.fetch(id).fetch("overall_score") != current.fetch(id).fetch("overall_score") },
  "context_path" => context_path, "driver_sha256" => LocalEvalArtifact.sha256(__FILE__) }
File.write(File.join(evidence, "release-integration.json"), JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(evidence, File.basename(__FILE__)))
FileUtils.cp(__FILE__, File.join(root, base, "completion", File.basename(__FILE__)))
puts JSON.pretty_generate(report)
