#!/usr/bin/env ruby
# frozen_string_literal: true

# Compact Terra evidence; the established exporters own validation, corrections
# and measurements. This exporter does not execute generated programs.
require_relative "artifact_common"
require_relative "../method/codex-usage/codex_usage"

module Terra61Supplement
  BATCH = "20261028-200951"
  ORIGINAL = "c94e9a7be1efbb0235af8cd31fdb9f5c7b994a36"
  POLICY = "luna_first_uncertainty_or_disagreement_v1"
  module_function

  def run(root:, home:, phase:)
    raise "Unknown supplement phase" unless %w[audit complete].include?(phase)
    batch = File.join(root, "batches", BATCH)
    campaign = File.join(home, "llm_para_campaigns/#{BATCH}-terra61-codex-medium")
    evaluation = File.join(campaign, "evaluation")
    audit = File.join(home, "llm_timing_audit/20261029-terra61-codex")
    raise "Export native validation first" unless File.file?(File.join(batch, "validation/records.jsonl"))
    write = lambda do |relative, bytes|
      raise "Unsafe export path" if Pathname.new(relative).absolute? || relative.split('/').include?('..')
      target = File.join(batch, relative)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, bytes)
    end
    json = ->(relative, value) { write.call(relative, JSON.pretty_generate(value) + "\n") }
    jsonl = ->(relative, rows) { write.call(relative, rows.map { |row| JSON.generate(row) + "\n" }.join) }
    copy = ->(source, relative) { write.call(relative, File.binread(source)) }
    selected = lambda do |source, destination, names|
      names.each do |name|
        file = File.join(source, name)
        copy.call(file, "#{destination}/#{name}") if File.file?(file)
      end
    end
    report = JSON.parse(File.read(File.join(evaluation, "audit-completion-review.json")))
    expected_ids = LocalEvalArtifact.read_jsonl(File.join(batch, "validation/records.jsonl")).select do |row|
      info = row.fetch("metadata")
      LocalEvalArtifact::VALIDATION_STAGES.all? { |stage| info.fetch("stages").fetch(stage) == true } &&
        (%w[mpi hybrid].include?(info.fetch("par_type")) || info.fetch("benchmark") == "qtclustering")
    end.map { |row| row.fetch("id") }.sort
    raise "Audit unresolved" unless report.fetch("passed") && report.fetch("unique_programs") == expected_ids.size && report.fetch("unresolved").empty?
    report.fetch("input_sha256").each do |path, digest|
      raise "Audit input changed" unless LocalEvalArtifact.sha256(path) == digest
    end

    if phase == "audit"
      { "primary" => audit, "priority" => "#{audit}-priority", "adjudication" => "#{audit}-sol61" }.each do |label, source|
        selected.call(source, "timing-audit/#{label}", %w[pilot-review.json operational-provenance.json
          static-evidence-snapshot.rb review-policy-snapshot.rb active-review-policy-full.rb
          adjudication-plan-full.json adjudication-selection.jsonl])
      end
      %w[qtclustering qtclustering-sol61].each do |suffix|
        source = "#{audit}-#{suffix}"
        destination = "timing-audit/#{suffix}"
        expected = report.fetch("reviews").find { |row| row.fetch("root") == source }
        raise "Unbound QT manifest" unless expected && LocalEvalArtifact.sha256(File.join(source, "manifest.yaml")) == expected.fetch("manifest_sha256")
        selected.call(source, destination, %w[manifest.yaml inventory.jsonl excluded.jsonl trial-ids.txt
          prompt-template.txt result-schema.json runner-snapshot.rb static-evidence-snapshot.rb preparer-snapshot.rb
          summary-full.jsonl summary-full.csv summary-trial.jsonl summary-trial.csv review-guidance.txt platform-context.txt
          comparison.jsonl comparison.csv operational-provenance.json review-policy-snapshot.rb active-review-policy-full.rb
          adjudication-plan-full.json adjudication-selection.jsonl pilot-review.json])
        results = Dir[File.join(source, "results/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
        ids = if suffix == "qtclustering-sol61"
          plan = JSON.parse(File.read(File.join(source, "adjudication-plan-full.json")))
          raise "Wrong QT adjudication policy" unless plan.fetch("policy") == POLICY
          LocalEvalArtifact.read_jsonl(File.join("#{audit}-qtclustering", "final/decisions.jsonl"))
            .select { |row| row["adjudication_verdict"] }.map { |row| row.fetch("program_id") }.sort
        else
          LocalEvalArtifact.read_jsonl(File.join(source, "inventory.jsonl")).map { |row| row.fetch("id") }.sort
        end
        raise "QT result scope differs" unless results.size == expected.fetch("responses") && results.map { |row| row.fetch("program_id") }.sort == ids
        jsonl.call("#{destination}/results.jsonl", results)
        attempts = Dir[File.join(source, "logs/*/attempt-*/metadata.yaml")].sort.map do |path|
          metadata = LocalEvalArtifact.load_yaml(path)
          events = LocalEvalArtifact.read_jsonl(File.join(File.dirname(path), "events.jsonl"))
          raise "Non-static QT review event" if events.any? { |event| event["item"] && !%w[agent_message reasoning error].include?(event.fetch("item")["type"]) }
          errors = events.filter_map { |event| event["message"] if event["type"] == "error" }.uniq
          metadata["exported_transport_errors"] = errors unless errors.empty?
          metadata
        end
        raise "QT attempt scope differs" unless attempts.size == expected.fetch("retained_attempts") && expected.fetch("prohibited_tool_events").zero?
        jsonl.call("#{destination}/attempts.jsonl", attempts)
        Dir[File.join(source, "final/*")].sort.each { |path| copy.call(path, "#{destination}/final/#{File.basename(path)}") if File.file?(path) }
      end
      decisions = {}
      inputs = %w[primary qtclustering].map do |stage|
        relative = "timing-audit/#{stage}/final/decisions.jsonl"
        LocalEvalArtifact.read_jsonl(File.join(batch, relative)).each do |row|
          id = row.fetch("program_id")
          raise "Overlay source changed" if decisions[id] && decisions.fetch(id).fetch("source_digest") != row.fetch("source_digest")
          decisions[id] = row
        end
        { "path" => relative, "sha256" => LocalEvalArtifact.sha256(File.join(batch, relative)) }
      end
      raise "Audit coverage differs" unless decisions.keys.sort == expected_ids
      counts = decisions.values.group_by { |row| row.fetch("final_verdict") }.transform_values(&:size)
      raise "Audit counts differ" unless counts == report.fetch("verdicts")
      correction_ids = decisions.values.select { |row| row.fetch("timing_fix_required") }.map { |row| row.fetch("program_id") }.sort
      raise "Unresolved audit conditions" unless decisions.values.all? { |row| row.fetch("timing_review_required") == false }
      json.call("timing-audit/resolved-selection.json", {
        "schema_version" => 1, "source_commit" => ORIGINAL, "record_count" => decisions.size,
        "ordered_decisions" => inputs, "verdict_counts" => counts, "correction_ids" => correction_ids,
        "policy" => "Same-source all-backend QT boundary decisions overlay the general MPI/hybrid audit; all review evidence is retained."
      })
      write.call("timing-audit/conditional-decisions.jsonl", "")
      selected.call(evaluation, "completion", %w[audit-completion-review.json verify-audit-completion.rb review-policy.json
        prepare-review-policy.rb verify-primary-pilot.rb audit-pilot-driver.rb audit-full-driver-policy.rb
        audit-pilot-launch.json audit-full-launch.json timing-platform-context.txt
        pilot-source-quality-review.json record-pilot-source-check.rb])
      summary = JSON.parse(File.read(File.join(batch, "summary.json")))
      summary["timing_audit_final_verdicts"] = counts
      %w[qtclustering qtclustering-sol61].each do |suffix|
        summary.fetch("timing_audit_records")[suffix] = report.fetch("reviews")
          .find { |row| row.fetch("root") == "#{audit}-#{suffix}" }.fetch("responses")
      end
      summary["timing_audit_selection"] = "timing-audit/resolved-selection.json"
      summary["unique_timing_audited_programs"] = decisions.size
      json.call("summary.json", summary)
      puts "Retained five audit stages, #{decisions.size} resolved programs, #{correction_ids.size} timing corrections."
      return
    end

    raise "Export native aggregate first" unless File.file?(File.join(batch, "aggregate/export.json"))
    completion = JSON.parse(File.read(File.join(campaign, "completion-audit.json")))
    raise "Generation completion changed" unless completion.fetch("source_commit") == ORIGINAL &&
      completion.fetch("observations") == 220 && completion.fetch("outcomes") == { "completed" => 220 } &&
      completion.fetch("accepted_generation_invocations") == 220 && completion.fetch("usage_complete")
    selected.call(campaign, "generation", %w[campaign.json run-ids.txt preflight-ids.txt preflight-gate.json
      preflight-review.json filesystem-preflight.json model-access.json tool-host-amendment.json
      completion.json completion-audit.json usage-recovery.json preflight-usage-recovery.json
      preflight-launch.json run-launch.json source-retention-push.json])
    selected.call(campaign, "generation/supervision", %w[prepare-campaign.rb inspect-model-access.rb run.rb
      controller.rb monitor.rb launch.rb review-preflight.rb amend-tool-host.rb audit-completion.rb])
    manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
    raise "Generation identity changed" unless manifest.fetch("campaign_id") == BATCH
    reusable = {}
    LocalEvalArtifact.regular_files(root).each do |path|
      relative = LocalEvalArtifact.relative_path(root, path)
      next unless relative.start_with?("method/") || relative.match?(%r{\Abatches/[^/]+/(?:method|generation/(?:method|runtime-method)|timing-corrections/method|benchmark/method)/})
      reusable[LocalEvalArtifact.sha256(path)] ||= relative
    end
    layout = manifest.fetch("files").to_h do |name, digest|
      raise "Unsafe method path" if Pathname.new(name).absolute? || name.split('/').include?('..')
      source = File.join(campaign, "method", name)
      raise "Generation method changed: #{name}" unless LocalEvalArtifact.sha256(source) == digest
      relative = reusable[digest]
      unless relative
        stored = "generation/method/#{name.gsub('/bin/', '/commands/')}"
        copy.call(source, stored)
        relative = "batches/#{BATCH}/#{stored}"
        reusable[digest] = relative
      end
      [name, relative]
    end
    json.call("generation/method-layout.json", layout)
    observations = Dir[File.join(campaign, "observations/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
    usage_path = File.join(campaign, "codex-usage.jsonl")
    usage = CodexUsage.load_records(usage_path)
    receipt = JSON.parse(File.read(File.join(campaign, "usage-recovery.json")))
    raise "Usage receipt changed" unless receipt.fetch("records") == 220 && receipt.fetch("unavailable").empty? &&
      receipt.fetch("sha256") == LocalEvalArtifact.sha256(usage_path) && receipt.fetch("sha256") == completion.fetch("usage_sha256")
    raise "Generation scope differs" unless observations.size == 220 && observations.map { |row| row.fetch("id") }.sort == usage.keys.sort
    observations.each do |observation|
      record = usage.fetch(observation.fetch("id"))
      raise "Generation identity differs" unless observation.fetch("outcome") == "completed" &&
        observation.fetch("model") == "gpt-6.1-terra" && observation.fetch("reasoning_effort") == "medium" &&
        observation.fetch("session_id") == record.fetch("session_id") &&
        observation.fetch("sha256").fetch("output.txt") == record.fetch("transcript_sha256")
    end
    usage_destination = File.join(root, "metadata/codex-usage/#{BATCH}.jsonl")
    FileUtils.mkdir_p(File.dirname(usage_destination))
    FileUtils.cp(usage_path, usage_destination)
    jsonl.call("generation/observations.jsonl", observations)
    jsonl.call("generation/cleanup.jsonl", Dir[File.join(campaign, "cleanup/*.json")].sort.map { |path| JSON.parse(File.read(path)) })
    completion.fetch("unaccepted_setup_attempts").each do |attempt|
      source = File.join(campaign, attempt.fetch("path"))
      raise "Setup evidence changed" unless LocalEvalArtifact.sha256(source) == attempt.fetch("sha256")
      selected.call(File.dirname(source), "generation/#{File.dirname(attempt.fetch('path'))}",
        %w[review.json campaign.json filesystem-preflight.json preflight-gate.json preflight-usage-recovery.json])
    end
    completion.fetch("provider_capacity_recoveries").each do |attempt|
      source = File.join(campaign, attempt.fetch("recovery_path"))
      raise "Capacity evidence changed" unless LocalEvalArtifact.sha256(source) == attempt.fetch("recovery_sha256") &&
        LocalEvalArtifact.sha256(File.join(File.dirname(source), "retry-completed.json")) == attempt.fetch("retry_completion_sha256")
      relative = "generation/#{File.dirname(attempt.fetch('recovery_path'))}"
      selected.call(File.dirname(source), relative, %w[recovery.json retry-completed.json cleanup.json archival-complete.json])
      selected.call(File.join(File.dirname(source), "output"), relative, %w[timing.txt process-status.txt])
    end
    pricing = File.join(campaign, "pricing")
    audit_report = JSON.parse(File.read(File.join(pricing, "request-pricing-audit.json")))
    raise "Pricing scope changed" unless audit_report.fetch("observations") == 220 &&
      audit_report.fetch("profile") == "gpt-6.1-terra-medium" && audit_report.fetch("generation_complete_before_session_inspection") &&
      audit_report.fetch("final_usage_sha256") == LocalEvalArtifact.sha256(usage_path) &&
      audit_report.fetch("pricing_reference_sha256") == LocalEvalArtifact.sha256(File.join(pricing, "pricing-reference.json")) &&
      audit_report.fetch("request_usage_sha256") == LocalEvalArtifact.sha256(File.join(pricing, "codex-request-usage.jsonl")) &&
      audit_report.fetch("by_context_tier").fetch("long").fetch("requests").zero? &&
      audit_report.fetch("cache_write_input_tokens_known_zero")
    selected.call(pricing, "generation/pricing", %w[pricing-reference.json source-capture.json request-pricing-audit.json
      codex-request-usage.jsonl read-request-usage.rb test-request-usage.rb audit-pricing.rb])
    selected.call(evaluation, "completion", %w[campaign.json review-tooling.json timing-platform-context.txt
      validation-launch-gate.json validation-completion-review.json correction-pilot-gate.json correction-commit.json
      revalidation-completion-review.json benchmark-canary-gate.json benchmark-completion-review.json benchmark-progress.json
      verify-validation-completion.rb verify-correction-pilot.rb verify-revalidation-completion.rb verify-benchmark-records.rb
      commit-corrections.rb benchmark-driver.rb prepare-release-export.rb export-completed-batch.rb])
    summary = JSON.parse(File.read(File.join(batch, "summary.json")))
    summary["benchmarking_performed"] = true
    summary.fetch("timing_corrections")["benchmarking_performed"] = true if summary["timing_corrections"]
    summary["generation"] = { "records" => 220, "exact_counters_verified" => 220,
      "provider_capacity_retries" => completion.fetch("provider_capacity_recoveries").size,
      "excluded_setup_attempts" => completion.fetch("unaccepted_setup_attempts").size }
    json.call("summary.json", summary)
    puts "Retained 220 exact Terra generation observations, compact request-level pricing and campaign provenance."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} audit|complete HOME" unless ARGV.size == 2 && %w[audit complete].include?(ARGV.first)
  Terra61Supplement.run(root: File.expand_path("..", __dir__), home: File.expand_path(ARGV.last), phase: ARGV.first)
end
