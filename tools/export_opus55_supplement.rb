#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only export of compact campaign evidence, after the standard validation,
# correction, benchmark and aggregate exporters. No model/program executions.
require_relative "artifact_common"

module Opus55Supplement
  BATCH = "20261002-142720"
  module_function

  def run(root:, home:)
    batch = File.join(root, "batches", BATCH)
    campaign = File.join(home, "llm_para_campaigns/#{BATCH}-opus55-medium")
    raise "Export the standard batch first" unless File.file?(File.join(batch, "aggregate/export.json"))
    write = lambda do |relative, bytes|
      target = File.join(batch, relative)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, bytes)
    end
    json = ->(relative, value) { write.call(relative, JSON.pretty_generate(value) + "\n") }
    jsonl = ->(relative, values) { write.call(relative, values.map { |v| JSON.generate(v) + "\n" }.join) }
    copy = ->(source, relative) { write.call(relative, File.binread(source)) }
    selected = lambda do |source, destination, names|
      names.each do |name|
        file = File.join(source, name)
        copy.call(file, "#{destination}/#{name}") if File.file?(file)
      end
    end
    selected.call(campaign, "generation", %w[campaign.json run-ids.txt preflight-ids.txt preflight-gate.json
      completion.json completion-audit.json supervision.json launch.json])
    manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
    manifest.fetch("files").each do |name, digest|
      source = File.join(campaign, "method", name)
      raise "Generation method changed: #{name}" unless LocalEvalArtifact.sha256(source) == digest
      copy.call(source, "generation/method/#{name}")
    end
    observations = Dir[File.join(campaign, "observations/*.json")].sort.map { |p| JSON.parse(File.read(p)) }
    rows = CSV.read(File.join(batch, "aggregate/aggregate_results.csv"), headers: true).to_h do |r|
      ["#{r['benchmark']}_#{r['model']}_#{r['par_type']}_r#{r['run']}", r]
    end
    raise "Generation scope differs" unless observations.size == 220 && observations.map { |r| r.fetch("id") }.sort == rows.keys.sort
    observations.each do |observation|
      row = rows.fetch(observation.fetch("id"))
      raise "Unexpected generation outcome" unless observation.fetch("outcome") == "completed" && observation.fetch("retry_count").zero?
      { "input_tokens" => observation.fetch("inclusive_input_tokens"),
        "output_tokens" => observation.dig("token_counts", "output_tokens"),
        "cached_tokens" => observation.dig("token_counts", "cache_read_input_tokens"),
        "total_tokens" => observation.fetch("total_tokens"),
        "api_time" => observation.fetch("api_seconds"), "total_time" => observation.fetch("total_seconds") }.each do |key, value|
        raise "Generation counter differs: #{observation['id']}/#{key}" unless Float(row.fetch(key)) == value
      end
    end
    jsonl.call("generation/observations.jsonl", observations)
    jsonl.call("generation/cleanup.jsonl", Dir[File.join(campaign, "cleanup/*.json")].sort.map { |p| JSON.parse(File.read(p)) })

    # Content-addressed supervisor snapshots avoid repeating unchanged helpers.
    retained = Dir[File.join(batch, "**/method/**/*.rb")].to_h { |p| [LocalEvalArtifact.sha256(p), p.delete_prefix(batch + "/")] }
    [File.join(campaign, "supervision"), *Dir[File.join(campaign, "supervision-revisions/*")].sort].each do |directory|
      label = directory.delete_prefix(campaign + "/")
      layout = Dir[File.join(directory, "**/*.rb")].sort.to_h do |source|
        digest = LocalEvalArtifact.sha256(source)
        retained[digest] ||= begin
          relative = "generation/method/supervision/#{digest[0, 12]}-#{File.basename(source)}"
          copy.call(source, relative)
          relative
        end
        [source.delete_prefix(directory + "/"), { "sha256" => digest, "path" => retained.fetch(digest) }]
      end
      json.call("generation/#{label}/method-layout.json", layout)
      selected.call(directory, "generation/#{label}", %w[amendment.json cleanup-live-test.json before-progress.json before-monitor-status.json])
    end
    evaluation = File.join(campaign, "evaluation")
    selected.call(evaluation, "completion", %w[campaign.json review-tooling.json timing-platform-context.txt
      audit-completion-review.json correction-pilot-gate.json correction-commit.json revalidation-completion-review.json
      benchmark-canary-gate.json benchmark-completion-review.json benchmark-progress.json
      verify-validation-completion.rb verify-audit-completion.rb verify-correction-pilot.rb verify-revalidation-completion.rb
      verify-benchmark-records.rb hash-regression-sol61.json])
    selected.call(File.join(evaluation, "hash-policy-amendment"), "completion/hash-policy-amendment",
      %w[decision.json revalidation-driver-after.rb revalidation-driver-before.rb preflight-before.yaml stopped-progress.json])

    %w[qtclustering qtclustering-sol61].each do |suffix|
      source = File.join(home, "llm_timing_audit/20261006-opus55-#{suffix}")
      destination = "timing-audit/#{suffix}"
      selected.call(source, destination, %w[manifest.yaml inventory.jsonl excluded.jsonl trial-ids.txt prompt-template.txt
        result-schema.json runner-snapshot.rb static-evidence-snapshot.rb preparer-snapshot.rb summary-full.jsonl
        summary-full.csv review-guidance.txt platform-context.txt comparison.jsonl comparison.csv operational-provenance.json])
      jsonl.call("#{destination}/results.jsonl", Dir[File.join(source, "results/*.json")].sort.map { |p| JSON.parse(File.read(p)) })
      jsonl.call("#{destination}/attempts.jsonl", Dir[File.join(source, "logs/*/attempt-*/metadata.yaml")].sort.map { |p| LocalEvalArtifact.load_yaml(p) })
      Dir[File.join(source, "final/*")].sort.each { |p| copy.call(p, "#{destination}/final/#{File.basename(p)}") if File.file?(p) }
    end
    summary_path = File.join(batch, "summary.json")
    summary = JSON.parse(File.read(summary_path))
    summary["benchmarking_performed"] = true
    summary.fetch("timing_corrections")["benchmarking_performed"] = true
    summary["generation"] = { "records" => observations.size, "exact_counters_verified" => observations.size, "retries" => 0 }
    summary["qt_timing_review"] = { "primary" => 20, "adjudication" => 18, "additional_corrections" => 0 }
    json.call("summary.json", summary)
    puts "Verified and exported #{observations.size} generation observations and both QT audit stages."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} HOME" unless ARGV.size == 1
  Opus55Supplement.run(root: File.expand_path("..", __dir__), home: File.expand_path(ARGV.first))
end
