#!/usr/bin/env ruby
# frozen_string_literal: true

# Compact Haiku evidence; standard exporters own validation and measurements.
require_relative "artifact_common"

module Haiku55Supplement
  BATCH = "20261012-111947"
  ORIGINAL = "71ba7cc523997c8fd1537d7a8159b583f260793d"
  POLICY = "luna_first_uncertainty_or_disagreement_v1"
  module_function

  def run(root:, home:, phase:)
    batch = File.join(root, "batches", BATCH)
    campaign = File.join(home, "llm_para_campaigns/#{BATCH}-haiku55-medium")
    evaluation = File.join(campaign, "evaluation")
    audit = File.join(home, "llm_timing_audit/20261014-haiku55")
    raise "Export standard validation first" unless File.file?(File.join(batch, "validation/records.jsonl"))
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
    raise "Audit not resolved" unless report.fetch("passed") && report.fetch("unique_programs") == 119 && report.fetch("unresolved").empty?
    report.fetch("input_sha256").each do |path, digest|
      raise "Audit input changed" unless LocalEvalArtifact.sha256(path) == digest
    end

    if phase == "audit"
      %w[qtclustering qtclustering-sol61].each do |suffix|
        source = "#{audit}-#{suffix}"
        destination = "timing-audit/#{suffix}"
        expected = report.fetch("reviews").find { |row| row.fetch("root") == source }
        raise "Unbound audit manifest" unless expected && LocalEvalArtifact.sha256(File.join(source, "manifest.yaml")) == expected.fetch("manifest_sha256")
        selected.call(source, destination, %w[manifest.yaml inventory.jsonl excluded.jsonl trial-ids.txt prompt-template.txt
          result-schema.json runner-snapshot.rb static-evidence-snapshot.rb preparer-snapshot.rb summary-full.jsonl
          summary-full.csv summary-trial.jsonl summary-trial.csv review-guidance.txt platform-context.txt comparison.jsonl
          comparison.csv operational-provenance.json review-policy-snapshot.rb active-review-policy-full.rb
          adjudication-plan-full.json adjudication-selection.jsonl pilot-review.json])
        results = Dir[File.join(source, "results/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
        selected_ids = if suffix == "qtclustering-sol61"
          plan = JSON.parse(File.read(File.join(source, "adjudication-plan-full.json")))
          raise "Wrong QT policy" unless plan.fetch("policy") == POLICY
          # Final decisions bind both retained legacy pilot responses and any
          # newly justified escalations; a retained review is never repeated.
          LocalEvalArtifact.read_jsonl(File.join("#{audit}-qtclustering", "final/decisions.jsonl"))
            .select { |row| row["adjudication_verdict"] }.map { |row| row.fetch("program_id") }.sort
        else
          LocalEvalArtifact.read_jsonl(File.join(source, "inventory.jsonl")).map { |row| row.fetch("id") }.sort
        end
        raise "QT result scope differs" unless results.size == expected.fetch("responses") && results.map { |row| row.fetch("program_id") }.sort == selected_ids
        jsonl.call("#{destination}/results.jsonl", results)
        attempts = Dir[File.join(source, "logs/*/attempt-*/metadata.yaml")].sort.map do |path|
          metadata = LocalEvalArtifact.load_yaml(path)
          events = LocalEvalArtifact.read_jsonl(File.join(File.dirname(path), "events.jsonl"))
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
      json.call("timing-audit/resolved-selection.json", {
        "schema_version" => 1, "source_commit" => ORIGINAL, "record_count" => decisions.size,
        "ordered_decisions" => inputs, "verdict_counts" => counts, "correction_ids" => correction_ids,
        "policy" => "Later same-source QT boundary decisions overlay the general audit; all original review evidence is retained."
      })
      write.call("timing-audit/conditional-decisions.jsonl", "")
      selected.call(evaluation, "completion", %w[audit-completion-review.json verify-audit-completion.rb review-policy-continuation.json
        review-cli-path-recovery.json audit-full-driver-policy.rb resume-audit-full.rb resume-qt-pilot.rb
        qt-review-policy-tests-host.log])
      %w[review-provider-recovery full-review-provider-recovery].each do |name|
        selected.call(File.join(evaluation, name), "completion/#{name}", %w[request.json initial-stop.json])
      end
      Dir[File.join(evaluation, "review-policy-method/**/*")].select { |path| File.file?(path) }.each do |path|
        relative = path.delete_prefix(File.join(evaluation, "review-policy-method") + "/").gsub("/bin/", "/commands/")
        copy.call(path, "timing-audit/review-policy-method/#{relative}")
      end
      summary = JSON.parse(File.read(File.join(batch, "summary.json")))
      summary["timing_audit_final_verdicts"] = counts
      summary.fetch("timing_audit_records").merge!("qtclustering" => 20, "qtclustering-sol61" => 16)
      summary["timing_audit_selection"] = "timing-audit/resolved-selection.json"
      summary["unique_timing_audited_programs"] = decisions.size
      json.call("summary.json", summary)
      puts "Retained five audit stages, #{decisions.size} resolved programs, #{correction_ids.size} timing corrections."
      return
    end

    raise "Export aggregate first" unless File.file?(File.join(batch, "aggregate/export.json"))
    selected.call(campaign, "generation", %w[campaign.json run-ids.txt preflight-ids.txt preflight-gate.json
      claude-preflight.json preflight-review.json completion.json completion-audit.json supervision.json launch.json])
    selected.call(campaign, "generation/supervision", %w[prepare.rb run.rb monitor.rb inspect_claude.rb
      verify-preflight.rb capture-launch.rb audit-completion.rb])
    reusable = {}
    LocalEvalArtifact.regular_files(root).each do |path|
      relative = LocalEvalArtifact.relative_path(root, path)
      next unless relative.start_with?("method/") || relative.match?(%r{\Abatches/[^/]+/(?:method|generation/method|timing-corrections/method|benchmark/method)/})
      reusable[LocalEvalArtifact.sha256(path)] ||= relative
    end
    retain_method = lambda do |source, names, destination|
      names.to_h do |name, digest|
        file = File.join(source, name)
        raise "Method changed: #{file}" unless LocalEvalArtifact.sha256(file) == digest
        relative = reusable[digest]
        unless relative
          stored = "#{destination}/#{name.gsub('/bin/', '/commands/')}"
          copy.call(file, stored)
          relative = "batches/#{BATCH}/#{stored}"
          reusable[digest] = relative
        end
        [name, relative]
      end
    end
    manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
    json.call("generation/method-layout.json", retain_method.call(File.join(campaign, "method"), manifest.fetch("files"), "generation/method"))
    observations = Dir[File.join(campaign, "observations/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
    rows = CSV.read(File.join(batch, "aggregate/aggregate_results.csv"), headers: true).to_h do |row|
      ["#{row['benchmark']}_#{row['model']}_#{row['par_type']}_r#{row['run']}", row]
    end
    raise "Generation scope differs" unless observations.size == 220 && observations.map { |row| row.fetch("id") }.sort == rows.keys.sort
    observations.each do |observation|
      row = rows.fetch(observation.fetch("id"))
      raise "Unexpected generation outcome" unless observation.fetch("outcome") == "completed" && observation.fetch("retry_count").zero?
      { "input_tokens" => observation.fetch("inclusive_input_tokens"), "output_tokens" => observation.dig("token_counts", "output_tokens"),
        "cached_tokens" => observation.dig("token_counts", "cache_read_input_tokens"), "total_tokens" => observation.fetch("total_tokens"),
        "api_time" => observation.fetch("api_seconds"), "total_time" => observation.fetch("total_seconds") }.each do |key, value|
        raise "Generation counter differs #{observation['id']}/#{key}" unless Float(row.fetch(key)) == value
      end
    end
    jsonl.call("generation/observations.jsonl", observations)
    jsonl.call("generation/cleanup.jsonl", Dir[File.join(campaign, "cleanup/*.json")].sort.map { |path| JSON.parse(File.read(path)) })
    context = File.join(campaign, "context-usage")
    recovery = JSON.parse(File.read(File.join(context, "recovery.json")))
    usage = LocalEvalArtifact.read_jsonl(File.join(context, "usage.jsonl"))
    raise "Context evidence differs" unless recovery.fetch("records") == 220 && recovery.fetch("usage_sha256") == LocalEvalArtifact.sha256(File.join(context, "usage.jsonl")) &&
      usage.map { |row| row.fetch("id") }.sort == rows.keys.sort && usage.all? { |row| row.fetch("source_commit") == ORIGINAL }
    selected.call(context, "generation/context-usage", %w[usage.jsonl recovery.json pricing-reference.json openrouter-endpoints.json regression-tests.log])
    json.call("generation/context-usage/method-layout.json", retain_method.call(File.join(context, "method"), recovery.fetch("method_files"), "generation/context-usage/method"))
    selected.call(evaluation, "completion", %w[campaign.json review-tooling.json timing-platform-context.txt
      validation-launch-gate.json validation-completion-review.json correction-pilot-gate.json correction-commit.json
      revalidation-completion-review.json benchmark-canary-gate.json benchmark-completion-review.json benchmark-progress.json
      verify-validation-completion.rb verify-correction-pilot.rb verify-revalidation-completion.rb verify-benchmark-records.rb
      commit-corrections.rb finalize-existing-correction.rb benchmark-driver.rb])
    selected.call(File.join(home, "llm_timing_fixes/20261014-haiku55-review"),
      "timing-corrections/postfix-review", %w[reused-reviews.json])
    summary = JSON.parse(File.read(File.join(batch, "summary.json")))
    summary["benchmarking_performed"] = true
    summary.fetch("timing_corrections")["benchmarking_performed"] = true
    summary["generation"] = { "records" => 220, "exact_counters_verified" => 220, "provider_retries" => 0,
      "request_context_usage" => "generation/context-usage/usage.jsonl", "long_context_observations" => recovery.fetch("records_with_long_context") }
    json.call("summary.json", summary)
    puts "Retained 220 generation observations and request-context pricing evidence."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} audit|complete HOME" unless ARGV.size == 2 && %w[audit complete].include?(ARGV.first)
  Haiku55Supplement.run(root: File.expand_path("..", __dir__), home: File.expand_path(ARGV.last), phase: ARGV.first)
end
