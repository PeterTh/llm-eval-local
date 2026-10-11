#!/usr/bin/env ruby
# frozen_string_literal: true

# Compact evidence only. Standard exporters own validation and measurements.
require_relative "artifact_common"
require_relative "../method/codex-usage/codex_usage"

module Sol61Supplement
  BATCH = "20261006-204623"
  ORIGINAL = "6adaf64dc195651e5b3da3575738874e09fdc72d"
  module_function

  def run(root:, home:, phase:)
    batch = File.join(root, "batches", BATCH)
    campaign = File.join(home, "llm_para_campaigns/#{BATCH}-sol61-medium-xhigh")
    evaluation = File.join(campaign, "evaluation")
    raise "Export the standard validation first" unless File.file?(File.join(batch, "validation/records.jsonl"))
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

    if phase == "audit"
      report = JSON.parse(File.read(File.join(evaluation, "audit-resolution-review.json")))
      raise "Audit not resolved" unless report.fetch("passed") && report.fetch("unique_programs") == 239 && report.fetch("unresolved").empty?
      %w[qtclustering qtclustering-sol61 mpi-split-supplemental].each do |suffix|
        source = File.join(home, "llm_timing_audit/20261010-sol61-#{suffix}")
        destination = "timing-audit/#{suffix}"
        expected = report.fetch("reviews").find { |record| record.fetch("root") == source }
        raise "Unbound audit manifest" unless expected && LocalEvalArtifact.sha256(File.join(source, "manifest.yaml")) == expected.fetch("manifest_sha256")
        selected.call(source, destination, %w[manifest.yaml inventory.jsonl excluded.jsonl trial-ids.txt prompt-template.txt
          result-schema.json runner-snapshot.rb static-evidence-snapshot.rb preparer-snapshot.rb summary-full.jsonl
          summary-full.csv review-guidance.txt platform-context.txt comparison.jsonl comparison.csv operational-provenance.json
          supplemental-selection.jsonl])
        results = Dir[File.join(source, "results/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
        inventory = LocalEvalArtifact.read_jsonl(File.join(source, "inventory.jsonl"))
        selected_ids = if suffix == "qtclustering-sol61"
          LocalEvalArtifact.read_jsonl(File.join(home, "llm_timing_audit/20261010-sol61-qtclustering/final/decisions.jsonl"))
            .select { |record| record["adjudication_verdict"] }.map { |record| record.fetch("program_id") }.sort
        else
          inventory.map { |record| record.fetch("id") }.sort
        end
        raise "Audit result scope differs" unless results.size == expected.fetch("responses") &&
          results.map { |record| record.fetch("program_id") }.sort == selected_ids
        jsonl.call("#{destination}/results.jsonl", results)
        attempts = Dir[File.join(source, "logs/*/attempt-*/metadata.yaml")].sort.map { |path| LocalEvalArtifact.load_yaml(path) }
        raise "Audit attempt scope differs" unless attempts.size == expected.fetch("attempts") && expected.fetch("prohibited_tool_events").zero?
        jsonl.call("#{destination}/attempts.jsonl", attempts)
        Dir[File.join(source, "final/*")].sort.each { |path| copy.call(path, "#{destination}/final/#{File.basename(path)}") if File.file?(path) }
      end
      decisions = {}
      inputs = %w[primary qtclustering mpi-split-supplemental].map do |stage|
        relative = "timing-audit/#{stage}/final/decisions.jsonl"
        digest = LocalEvalArtifact.sha256(File.join(batch, relative))
        native = File.join(home, "llm_timing_audit/20261010-sol61#{stage == 'primary' ? '' : '-' + stage}/final/decisions.jsonl")
        raise "Final audit input changed" unless report.fetch("input_sha256").fetch(native) == digest
        LocalEvalArtifact.read_jsonl(File.join(batch, relative)).each do |record|
          id = record.fetch("program_id")
          raise "Audit overlay source changed" if decisions[id] && decisions.fetch(id).fetch("source_digest") != record.fetch("source_digest")
          decisions[id] = record
        end
        { "path" => relative, "sha256" => digest }
      end
      expected_ids = LocalEvalArtifact.read_jsonl(File.join(batch, "validation/records.jsonl")).select do |record|
        stages = record.fetch("metadata").fetch("stages")
        info = record.fetch("metadata")
        LocalEvalArtifact::VALIDATION_STAGES.all? { |stage| stages.fetch(stage) == true } &&
          (%w[mpi hybrid].include?(info.fetch("par_type")) || info.fetch("benchmark") == "qtclustering")
      end.map { |record| record.fetch("id") }.sort
      raise "Resolved audit coverage differs" unless decisions.keys.sort == expected_ids
      counts = decisions.values.group_by { |record| record.fetch("final_verdict") }.transform_values(&:size)
      raise "Resolved audit counts differ" unless counts == report.fetch("verdicts")
      correction_ids = decisions.values.select { |record| record.fetch("timing_fix_required") }.map { |record| record.fetch("program_id") }.sort
      json.call("timing-audit/resolved-selection.json", {
        "schema_version" => 1, "source_commit" => ORIGINAL, "record_count" => decisions.size,
        "ordered_decisions" => inputs, "verdict_counts" => counts, "correction_ids" => correction_ids,
        "policy" => "Apply later same-source decisions in order. Earlier evidence is immutable; no scientific verdict is introduced by this selection."
      })
      # No remaining conditional decisions; the pinned MPI proof is retained below.
      write.call("timing-audit/conditional-decisions.jsonl", "")
      selected.call(evaluation, "completion", %w[audit-completion-review.json audit-resolution-review.json
        verify-audit-completion.rb verify-audit-resolution.rb finalize-supplemental.rb mpi-split-selection.jsonl])
      layout = Dir[File.join(evaluation, "mpi-split-evidence/*")].sort.to_h do |path|
        raise "Unexpected MPI evidence artifact" unless File.file?(path) && File.extname(path).match?(/\A\.(?:c|rb|txt|json)\z/)
        name = File.basename(path)
        stored = name.end_with?(".c") ? "#{name}.txt" : name
        copy.call(path, "timing-audit/mpi-split-evidence/#{stored}")
        [name, { "path" => stored, "sha256" => LocalEvalArtifact.sha256(path) }]
      end
      json.call("timing-audit/mpi-split-evidence/layout.json", layout)
      puts "Retained six audit stages and resolved #{decisions.size} programs into #{correction_ids.size} corrections."
      return
    end

    raise "Export the aggregate first" unless File.file?(File.join(batch, "aggregate/export.json"))
    selected.call(campaign, "generation", %w[campaign.json run-ids.txt preflight-ids.txt preflight-gate.json
      codex-preflight.json completion.json post-generation-verification.json usage-recovery.json preflight-usage-recovery.json])
    manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
    # Reuse byte-identical retained method files; store only this snapshot's deltas.
    reusable = {}
    LocalEvalArtifact.regular_files(root).each do |candidate|
      relative = LocalEvalArtifact.relative_path(root, candidate)
      next unless relative.start_with?("method/") || relative.match?(%r{\Abatches/[^/]+/(?:method|timing-corrections/method|benchmark/method)/})
      reusable[LocalEvalArtifact.sha256(candidate)] ||= relative
    end
    layout = manifest.fetch("files").to_h do |name, digest|
      source = File.join(campaign, "method", name)
      raise "Generation method changed: #{name}" unless LocalEvalArtifact.sha256(source) == digest
      relative = reusable[digest]
      unless relative
        stored = "generation/method/#{name.gsub('/bin/', '/commands/')}"
        copy.call(source, stored)
        relative = "batches/#{BATCH}/#{stored}"
      end
      [name, relative]
    end
    json.call("generation/method-layout.json", layout)
    selected.call(campaign, "generation/supervision", %w[prepare.rb inspect_codex.rb run.rb continue.rb monitor.rb verify_completion.rb record_capacity_recovery.rb])
    observations = Dir[File.join(campaign, "observations/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
    usage_path = File.join(campaign, "codex-usage.jsonl")
    usage = CodexUsage.load_records(usage_path)
    receipt = JSON.parse(File.read(File.join(campaign, "usage-recovery.json")))
    raise "Usage receipt changed" unless receipt.fetch("records") == 440 && receipt.fetch("unavailable").empty? && receipt.fetch("sha256") == LocalEvalArtifact.sha256(usage_path)
    raise "Generation observation scope differs" unless observations.size == 440 && observations.map { |record| record.fetch("id") }.sort == usage.keys.sort
    observations.each do |observation|
      record = usage.fetch(observation.fetch("id"))
      raise "Incomplete generation observation" unless observation.fetch("outcome") == "completed"
      raise "Generation usage identity differs" unless observation.fetch("session_id") == record.fetch("session_id") &&
        observation.fetch("sha256").fetch("output.txt") == record.fetch("transcript_sha256")
    end
    destination = File.join(root, "metadata/codex-usage/#{BATCH}.jsonl")
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(usage_path, destination)
    jsonl.call("generation/observations.jsonl", observations)
    jsonl.call("generation/cleanup.jsonl", Dir[File.join(campaign, "cleanup/*.json")].sort.map { |path| JSON.parse(File.read(path)) })
    Dir[File.join(campaign, "failed-attempts/*/attempt-*")].sort.each do |directory|
      relative = directory.delete_prefix(campaign + "/")
      selected.call(directory, "generation/#{relative}", %w[recovery.json retry-completed.json cleanup.json recover_capacity_attempt.rb])
      selected.call(File.join(directory, "output"), "generation/#{relative}", %w[timing.txt process-status.txt])
    end
    selected.call(evaluation, "completion", %w[campaign.json review-tooling.json timing-platform-context.txt
      validation-launch-gate.json validation-completion-review.json validation-disposition.json
      correction-pilot-gate.json correction-commit.json revalidation-completion-review.json
      benchmark-canary-gate.json benchmark-completion-review.json benchmark-progress.json
      verify-validation-completion.rb verify-correction-pilot.rb verify-revalidation-completion.rb verify-benchmark-records.rb
      commit-corrections.rb finalize-existing-correction.rb benchmark-driver.rb])
    summary = JSON.parse(File.read(File.join(batch, "summary.json")))
    summary["benchmarking_performed"] = true
    summary.fetch("timing_corrections")["benchmarking_performed"] = true
    summary["generation"] = { "records" => 440, "exact_counters_verified" => 440, "provider_capacity_retries" => 1 }
    summary["timing_audit_final_verdicts"] = { "valid" => 228, "invalid" => 11 }
    summary["timing_audit_records"].merge!("qtclustering" => 40, "qtclustering-sol61" => 19, "mpi-split-supplemental" => 1)
    summary["timing_audit_selection"] = "timing-audit/resolved-selection.json"
    summary["unique_timing_audited_programs"] = 239
    json.call("summary.json", summary)
    puts "Retained 440 exact generation observations and completed Sol 6.1 campaign evidence."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} audit|complete HOME" unless ARGV.size == 2 && %w[audit complete].include?(ARGV.first)
  Sol61Supplement.run(root: File.expand_path("..", __dir__), home: File.expand_path(ARGV.last), phase: ARGV.first)
end
