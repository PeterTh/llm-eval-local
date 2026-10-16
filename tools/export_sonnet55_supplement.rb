#!/usr/bin/env ruby
# frozen_string_literal: true

# Compact Sonnet evidence; standard exporters own validation and measurements.
require_relative "artifact_common"
require "open3"

module Sonnet55Supplement
  BATCH = "20261014-212207"
  ORIGINAL = "8fe249fe2622f21b32faf8d13cd290ce902f78cd"
  POLICY = "luna_first_uncertainty_or_disagreement_v1"
  module_function

  def run(root:, home:, phase:)
    batch = File.join(root, "batches", BATCH)
    campaign = File.join(home, "llm_para_campaigns/#{BATCH}-sonnet55-medium")
    evaluation = File.join(campaign, "evaluation")
    audit = File.join(home, "llm_timing_audit/20261015-sonnet55")
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
    report = JSON.parse(File.read(File.join(evaluation, "audit-resolution-review.json")))
    raise "Audit not resolved" unless report.fetch("passed") && report.fetch("unique_programs") == 115 && report.fetch("unresolved").empty?
    report.fetch("input_sha256").each do |path, digest|
      raise "Audit input changed" unless LocalEvalArtifact.sha256(path) == digest
    end

    if phase == "audit"
      %w[qtclustering qtclustering-sol61 mpi-split-supplemental].each do |suffix|
        source = "#{audit}-#{suffix}"
        destination = "timing-audit/#{suffix}"
        expected = report.fetch("reviews").find { |row| row.fetch("root") == source }
        raise "Unbound audit manifest" unless expected && LocalEvalArtifact.sha256(File.join(source, "manifest.yaml")) == expected.fetch("manifest_sha256")
        selected.call(source, destination, %w[manifest.yaml inventory.jsonl excluded.jsonl trial-ids.txt prompt-template.txt
          result-schema.json runner-snapshot.rb static-evidence-snapshot.rb preparer-snapshot.rb summary-full.jsonl
          summary-full.csv summary-trial.jsonl summary-trial.csv review-guidance.txt platform-context.txt comparison.jsonl
          comparison.csv operational-provenance.json review-policy-snapshot.rb active-review-policy-full.rb
          adjudication-plan-full.json adjudication-selection.jsonl pilot-review.json supplemental-selection.jsonl])
        results = Dir[File.join(source, "results/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
        selected_ids = if suffix == "qtclustering-sol61"
          plan = JSON.parse(File.read(File.join(source, "adjudication-plan-full.json")))
          raise "Wrong QT policy" unless plan.fetch("policy") == POLICY
          # Escalate only uncertainty or disagreement; completed pilot reviews
          # are reused, not repeated or escalated merely for pilot membership.
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
      inputs = %w[primary qtclustering mpi-split-supplemental].map do |stage|
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
        "policy" => "Later same-source QT boundary and focused supplemental decisions overlay the general audit in order; all original review evidence is retained."
      })
      write.call("timing-audit/conditional-decisions.jsonl", "")
      selected.call(evaluation, "completion", %w[audit-completion-review.json verify-audit-completion.rb review-policy.json
        prepare-review-policy.rb verify-primary-pilot.rb audit-pilot-driver.rb audit-full-driver-policy.rb
        audit-pilot-launch.json audit-full-launch.json audit-resolution-review.json verify-audit-resolution.rb
        finalize-supplemental.rb prepare-supplemental-review.rb audit-supplemental-driver.rb
        audit-supplemental-launch.json supplemental-driver-amendment.json adapt-supplemental-followup.rb])
      copy.call(File.join(evaluation, "mpi-split-selection.jsonl"), "completion/mpi-split-selection.jsonl")
      mpi_evidence = File.join(evaluation, "mpi-split-evidence")
      reuse = JSON.parse(File.read(File.join(mpi_evidence, "reuse-layout.json")))
      reuse.each_value do |entry|
        relative = entry.fetch("path")
        raise "Unexpected reused MPI evidence path" unless relative.start_with?("batches/20261006-204623/timing-audit/mpi-split-evidence/") && !relative.split('/').include?('..')
        raise "Reused MPI evidence changed" unless LocalEvalArtifact.sha256(File.join(root, relative)) == entry.fetch("sha256")
      end
      selected.call(mpi_evidence, "timing-audit/mpi-split-evidence", %w[evidence.json reuse-layout.json supplemental-context.txt
        program-dynamic-section.stdout.txt program-dynamic-section.stderr.txt packages.stdout.txt packages.stderr.txt])
      Dir[File.join(evaluation, "review-policy-method/**/*")].select { |path| File.file?(path) }.each do |path|
        relative = path.delete_prefix(File.join(evaluation, "review-policy-method") + "/").gsub("/bin/", "/commands/")
        copy.call(path, "timing-audit/review-policy-method/#{relative}")
      end
      summary = JSON.parse(File.read(File.join(batch, "summary.json")))
      summary["timing_audit_final_verdicts"] = counts
      %w[qtclustering qtclustering-sol61 mpi-split-supplemental].each do |suffix|
        summary.fetch("timing_audit_records")[suffix] = report.fetch("reviews")
          .find { |row| row.fetch("root") == "#{audit}-#{suffix}" }.fetch("responses")
      end
      summary["timing_audit_selection"] = "timing-audit/resolved-selection.json"
      summary["unique_timing_audited_programs"] = decisions.size
      json.call("summary.json", summary)
      puts "Retained six audit stages, #{decisions.size} resolved programs, #{correction_ids.size} timing corrections."
      return
    end

    raise "Export aggregate first" unless File.file?(File.join(batch, "aggregate/export.json"))
    selected.call(campaign, "generation", %w[campaign.json run-ids.txt preflight-ids.txt preflight-gate.json
      claude-preflight.json preflight-review.json completion.json completion-audit.json supervision.json launch.json
      resume-20261015.json source-retention-push.json])
    selected.call(campaign, "generation/supervision", %w[prepare.rb run.rb monitor.rb inspect_claude.rb
      verify-preflight.rb capture-launch.rb audit-completion.rb supervisor-run.rb revision-supervisor-run.rb])
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
    {
      "8164d46" => File.join(campaign, "supervision.json"),
      "3f380f9" => File.join(campaign, "supervision-3f380f9/revision.json")
    }.each do |revision, receipt_path|
      receipt = JSON.parse(File.read(receipt_path))
      raise "Generation method changed" unless receipt.fetch("generation_snapshot_unchanged") &&
        receipt.fetch("campaign_manifest_sha256") == LocalEvalArtifact.sha256(File.join(campaign, "campaign.json"))
      destination = "generation/supervision-#{revision}"
      copy.call(receipt_path, "#{destination}/revision.json")
      json.call("#{destination}/method-layout.json", retain_method.call(
        File.join(campaign, "supervision-#{revision}"), receipt.fetch("files"), "#{destination}/method"))
    end
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
    recoveries = observations.select { |row| row["generation_time_recovered"] == true }
    expected_recovery = "qtclustering_claude-sonnet-5.5-cc-medium_omp_r2"
    raise "Unexpected recovered observations" unless recoveries.map { |row| row.fetch("id") } == [expected_recovery]
    recoveries.each do |observation|
      id = observation.fetch("id")
      %w[generation_time_recovered generation_time_source wrapper_exit_status_available generation_recovery_sha256].each do |key|
        raise "Recovery provenance differs: #{key}" unless rows.fetch(id).fetch(key) == observation.fetch(key).to_s
      end
      bytes, status = Open3.capture2("git", "-C", File.join(home, "llm_para_experiments"), "show", "#{ORIGINAL}:#{BATCH}/#{id}/generation-recovery.txt")
      raise "Cannot read committed recovery evidence" unless status.success?
      raise "Recovery evidence changed" unless Digest::SHA256.hexdigest(bytes) == observation.fetch("generation_recovery_sha256") &&
        observation.fetch("sha256").fetch("generation-recovery.txt") == observation.fetch("generation_recovery_sha256")
      evidence = JSON.parse(bytes)
      raise "Wrong recovered native duration" unless evidence.fetch("run_id") == id &&
        evidence.fetch("campaign_id") == BATCH && evidence.fetch("duration_ms") / 1000.0 == observation.fetch("total_seconds") &&
        evidence.fetch("approved_by") == "user" && evidence.fetch("decision") == "retain_completed_native_result"
      write.call("generation/recoveries/#{id}.json", bytes)
    end
    jsonl.call("generation/observations.jsonl", observations)
    cleanup = Dir[File.join(campaign, "cleanup/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
    unless cleanup.map { |row| row.fetch("id") }.sort == rows.keys.sort - [expected_recovery] &&
           cleanup.all? { |row| row.fetch("verified_empty") }
      raise "Ordinary cleanup evidence differs"
    end
    jsonl.call("generation/cleanup.jsonl", cleanup)
    incident = File.join(campaign, "incidents/20261015-oom")
    raise "Recovered account was not verified idle" unless JSON.parse(File.read(File.join(incident, "incident.json"))).fetch("account_verified_idle")
    selected.call(incident, "generation/incidents/20261015-oom", %w[incident.json recovery.json service-journal.txt
      service-properties.txt pre-resume-service-properties.json STOP-before-resume recovery-regression-tests.log
      capture-oom-incident.rb recover-completed-observation.rb resume-after-oom.rb supervisor-run.rb])
    selected.call(File.join(campaign, "incidents/20261015-continuation"), "generation/incidents/20261015-continuation",
      %w[incident.json resume.json service-journal.txt service-properties.json STOP-before-resume
        continuation-regression-tests.log resume-after-continuation.rb revision-supervisor-run.rb])
    # Original code, transcripts, temporary dossiers and builds are already
    # reproducible or retained in their source repository; do not duplicate them.
    pricing = File.join(campaign, "pricing")
    price = JSON.parse(File.read(File.join(pricing, "pricing-reference.json")))
    raise "Pricing evidence changed" unless price.fetch("response_sha256") == LocalEvalArtifact.sha256(File.join(pricing, "openrouter-endpoints.json")) &&
      price.fetch("model") == "anthropic/claude-sonnet-5.5"
    selected.call(pricing, "generation/pricing", %w[pricing-reference.json openrouter-endpoints.json retain-pricing-preparation.rb])
    selected.call(evaluation, "completion", %w[campaign.json review-tooling.json timing-platform-context.txt
      validation-launch-gate.json validation-completion-review.json correction-pilot-gate.json correction-commit.json
      revalidation-completion-review.json benchmark-canary-gate.json benchmark-completion-review.json benchmark-progress.json
      verify-validation-completion.rb verify-correction-pilot.rb verify-revalidation-completion.rb verify-benchmark-records.rb
      commit-corrections.rb benchmark-driver.rb canary-driver.rb correction-pilot-driver.rb correction-full-driver.rb
      revalidation-driver.rb record-stage-launch.rb validation-launch.json correction-pilot-launch.json
      correction-full-launch.json revalidation-launch.json canary-launch.json benchmark-launch.json
      benchmark-driver-template-reuse.json prepare-benchmark-drivers.rb prepare-corrected-checkout.rb corrected-checkout.json
      benchmark-export-template-reuse.json prepare-benchmark-export.rb export-completed-batch.rb])
    selected.call(File.join(home, "llm_timing_fixes/20261015-sonnet55-review"),
      "timing-corrections/postfix-review", %w[reused-reviews.json])
    summary = JSON.parse(File.read(File.join(batch, "summary.json")))
    summary["benchmarking_performed"] = true
    summary.fetch("timing_corrections")["benchmarking_performed"] = true
    summary["generation"] = { "records" => 220, "exact_counters_verified" => 220, "provider_retries" => 0,
      "recovered_generation_durations" => recoveries.size, "ordinary_cleanup_records" => cleanup.size,
      "recovered_account_idle_evidence" => "generation/incidents/20261015-oom/incident.json",
      "pricing_reference" => "generation/pricing/pricing-reference.json" }
    json.call("summary.json", summary)
    puts "Retained 220 generation observations, one explicitly recovered duration, and pricing evidence."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} audit|complete HOME" unless ARGV.size == 2 && %w[audit complete].include?(ARGV.first)
  Sonnet55Supplement.run(root: File.expand_path("..", __dir__), home: File.expand_path(ARGV.last), phase: ARGV.first)
end
