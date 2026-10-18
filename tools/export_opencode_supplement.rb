#!/usr/bin/env ruby
# frozen_string_literal: true

# Compact OpenCode-specific evidence. Established exporters retain native
# validation, timing corrections and measurements; no generated programs run here.
require_relative "artifact_common"

module OpenCodeSupplement
  BATCH = "20261017-192226"
  ORIGINAL = "352c09d57e14ef93744aa8cc741ff52884079e5f"
  POLICY = "luna_first_uncertainty_or_disagreement_v1"
  module_function

  def run(root:, home:, phase:)
    raise "Unknown supplement phase" unless %w[audit complete].include?(phase)
    batch = File.join(root, "batches", BATCH)
    campaign = File.join(home, "llm_para_campaigns/#{BATCH}-sol61-opencode-medium")
    evaluation = File.join(campaign, "evaluation")
    audit = File.join(home, "llm_timing_audit/20261018-sol61-opencode")
    raise "Export native validation first" unless File.file?(File.join(batch, "validation/records.jsonl"))
    write = lambda do |relative, bytes|
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
    raise "Audit unresolved" unless report.fetch("passed") && report.fetch("unique_programs") == 119 && report.fetch("unresolved").empty?
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
      expected_ids = LocalEvalArtifact.read_jsonl(File.join(batch, "validation/records.jsonl")).select do |row|
        info = row.fetch("metadata")
        LocalEvalArtifact::VALIDATION_STAGES.all? { |stage| info.fetch("stages").fetch(stage) == true } &&
          (%w[mpi hybrid].include?(info.fetch("par_type")) || info.fetch("benchmark") == "qtclustering")
      end.map { |row| row.fetch("id") }.sort
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
        audit-pilot-launch.json audit-full-launch.json timing-platform-context.txt])
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
    selected.call(campaign, "generation", %w[campaign.json run-ids.txt preflight-ids.txt preflight-gate.json
      preflight-review.json completion.json completion-audit.json launch.json source-retention-push.json access-review.json])
    selected.call(campaign, "generation/supervision", %w[run.rb monitor.rb launch-full.rb review-preflight.rb
      verify-access-preserved.rb audit-completion.rb])
    reusable = {}
    LocalEvalArtifact.regular_files(root).each do |path|
      relative = LocalEvalArtifact.relative_path(root, path)
      next unless relative.start_with?("method/") || relative.match?(%r{\Abatches/[^/]+/(?:method|generation/method|timing-corrections/method|benchmark/method)/})
      reusable[LocalEvalArtifact.sha256(path)] ||= relative
    end
    manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
    layout = manifest.fetch("files").to_h do |name, digest|
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
    rows = CSV.read(File.join(batch, "aggregate/aggregate_results.csv"), headers: true).to_h do |row|
      ["#{row['benchmark']}_#{row['model']}_#{row['par_type']}_r#{row['run']}", row]
    end
    raise "Generation scope differs" unless observations.size == 220 && observations.map { |row| row.fetch("id") }.sort == rows.keys.sort
    require_relative "current_release"
    verifier = CurrentRelease.allocate
    verifier.verify_generation_observations!({ "id" => BATCH, "generation_harness" => "opencode" }, observations, rows)
    shared = observations.map { |row| row.slice("resolved_model", "tools") }.uniq
    raise "Multiple effective OpenCode configurations" unless shared.size == 1
    json.call("generation/common-configuration.json", shared.first)
    common_sha = LocalEvalArtifact.sha256(File.join(batch, "generation/common-configuration.json"))
    jsonl.call("generation/observations.jsonl", observations.map { |row| row.except("resolved_model", "tools").merge("common_configuration_sha256" => common_sha) })
    cleanup = Dir[File.join(campaign, "cleanup/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
    raise "Cleanup coverage differs" unless cleanup.map { |row| row.fetch("id") }.sort == rows.keys.sort && cleanup.all? { |row| row.fetch("verified_empty") }
    jsonl.call("generation/cleanup.jsonl", cleanup)
    %w[pilot-audit-visibility pilot-postprocessing].each do |incident|
      selected.call(File.join(campaign, "incidents", incident), "generation/incidents/#{incident}", %w[receipt.json])
    end
    pricing = File.join(campaign, "pricing")
    context = JSON.parse(File.read(File.join(pricing, "request-context-summary.json")))
    verifier.verify_opencode_context!({ "id" => BATCH, "source_commit" => ORIGINAL }, observations, context)
    selected.call(pricing, "generation/pricing", %w[pricing-reference.json request-context-summary.json retain-pricing-context.rb])
    selected.call(evaluation, "completion", %w[campaign.json validation-launch-gate.json validation-completion-review.json
      correction-pilot-gate.json correction-commit.json source-correction-push.json revalidation-completion-review.json
      benchmark-canary-gate.json benchmark-completion-review.json benchmark-progress.json
      verify-validation-completion.rb verify-correction-pilot.rb verify-revalidation-completion.rb verify-benchmark-records.rb
      commit-corrections.rb benchmark-driver.rb canary-driver.rb correction-pilot-driver.rb correction-full-driver.rb
      revalidation-driver.rb validation-launch.json correction-pilot-launch.json correction-full-launch.json
      revalidation-launch.json canary-launch.json benchmark-launch.json benchmark-driver-template-reuse.json
      prepare-benchmark-drivers.rb prepare-corrected-checkout.rb corrected-checkout.json correction-driver-template-reuse.json
      benchmark-export-template-reuse.json prepare-release-export.rb export-completed-batch.rb])
    selected.call(File.join(home, "llm_timing_fixes/20261018-sol61-opencode-review"),
      "timing-corrections/postfix-review", %w[reused-reviews.json])
    summary = JSON.parse(File.read(File.join(batch, "summary.json")))
    summary["benchmarking_performed"] = true
    summary.fetch("timing_corrections")["benchmarking_performed"] = true
    summary["generation"] = {
      "harness" => "opencode", "records" => 220, "exact_counters_verified" => 220,
      "native_requests" => context.fetch("requests"), "provider_retries" => observations.sum { |row| row.fetch("retry_count") },
      "excluded_retry_seconds" => observations.sum { |row| row.fetch("retry_backoff_seconds") }.round(6),
      "ordinary_cleanup_records" => cleanup.size, "api_time_available" => false,
      "common_configuration" => "generation/common-configuration.json", "pricing_reference" => "generation/pricing/pricing-reference.json"
    }
    json.call("summary.json", summary)
    puts "Retained 220 exact OpenCode observations, deduplicated configuration, cleanup and pricing evidence."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} audit|complete HOME" unless ARGV.size == 2
  OpenCodeSupplement.run(root: File.expand_path("..", __dir__), home: File.expand_path(ARGV.last), phase: ARGV.first)
end
