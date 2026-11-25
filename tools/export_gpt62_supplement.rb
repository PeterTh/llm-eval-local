#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'artifact_common'
require_relative 'gpt62_generation_evidence'

# Native exporters own validation, timing patches and measurements. This adds
# the reconciled timing selection and compact Codex generation provenance.
module Gpt62Supplement
  BATCH = Gpt62GenerationEvidence::BATCH
  ORIGINAL = Gpt62GenerationEvidence::ORIGINAL
  POLICY = 'luna_first_uncertainty_or_disagreement_v1'
  module_function

  def preserve_native_attempt_diagnostics(metadata, previous)
    return metadata unless previous
    native = previous.reject { |key, _| key.start_with?('exported_') }
    raise 'Previously exported attempt metadata changed' unless native == metadata
    previous.merge(metadata)
  end

  def run(root:, home:, phase:)
    raise 'Unknown supplement phase' unless %w[audit complete].include?(phase)
    batch = File.join(root, 'batches', BATCH)
    campaign = File.join(home, "llm_para_campaigns/#{BATCH}-gpt62-astra-sol-medium")
    evaluation = File.join(campaign, 'evaluation')
    audit = File.join(home, 'llm_timing_audit/20261125-gpt62-astra-sol-medium')
    raise 'Export native validation first' unless File.file?(File.join(batch, 'validation/records.jsonl'))
    write = lambda do |relative, bytes|
      Gpt62GenerationEvidence.safe_relative!(relative)
      target = File.join(batch, relative)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, bytes)
    end
    json = ->(relative, value) { write.call(relative, JSON.pretty_generate(value) + "\n") }
    jsonl = ->(relative, rows) { write.call(relative, rows.map { |row| JSON.generate(row) + "\n" }.join) }
    copy = ->(source, relative) { write.call(relative, File.binread(source)) }
    selected = lambda do |source, destination, names|
      names.each do |name|
        path = File.join(source, name)
        copy.call(path, "#{destination}/#{name}") if File.file?(path)
      end
    end
    report = JSON.parse(File.read(File.join(evaluation, 'audit-completion-review.json')))
    expected_ids = LocalEvalArtifact.read_jsonl(File.join(batch, 'validation/records.jsonl')).select do |row|
      info = row.fetch('metadata')
      LocalEvalArtifact::VALIDATION_STAGES.all? { |stage| info.fetch('stages').fetch(stage) == true } &&
        (%w[mpi hybrid].include?(info.fetch('par_type')) || info.fetch('benchmark') == 'qtclustering')
    end.map { |row| row.fetch('id') }.sort
    raise 'Audit unresolved' unless report.fetch('passed') && report.fetch('unresolved').empty? &&
      report.fetch('unique_programs') == expected_ids.size
    report.fetch('input_sha256').each do |path, digest|
      raise "Audit input changed: #{path}" unless LocalEvalArtifact.sha256(path) == digest
    end

    if phase == 'audit'
      stage_names = { audit => 'primary', audit + '-priority' => 'priority', audit + '-sol61' => 'adjudication' }
      report.fetch('reviews').each do |expected|
        source = expected.fetch('root')
        unless stage_names.key?(source)
          raise 'Unexpected audit root' unless source.start_with?(audit + '-')
          stage_names[source] = source.delete_prefix(audit + '-')
        end
        stage = stage_names.fetch(source)
        Gpt62GenerationEvidence.safe_relative!(stage)
        raise 'Unbound audit manifest' unless LocalEvalArtifact.sha256(File.join(source, 'manifest.yaml')) == expected.fetch('manifest_sha256')
        destination = "timing-audit/#{stage}"
        selected.call(source, destination, %w[manifest.yaml inventory.jsonl excluded.jsonl trial-ids.txt
          prompt-template.txt result-schema.json runner-snapshot.rb static-evidence-snapshot.rb preparer-snapshot.rb
          summary-full.jsonl summary-full.csv summary-trial.jsonl summary-trial.csv review-guidance.txt platform-context.txt
          comparison.jsonl comparison.csv operational-provenance.json review-policy-snapshot.rb active-review-policy-full.rb
          adjudication-plan-full.json adjudication-selection.jsonl supplemental-selection.jsonl pilot-review.json
          input-review-1.json input-review-2.json preprocessing-proof.json])
        Dir[File.join(source, 'prior-uncertain-review-*.json')].sort.each do |path|
          copy.call(path, "#{destination}/#{File.basename(path)}")
        end
        results = Dir[File.join(source, 'results/*.json')].sort.map { |path| JSON.parse(File.read(path)) }
        if stage == 'qtclustering-sol61'
          plan = JSON.parse(File.read(File.join(source, 'adjudication-plan-full.json')))
          raise 'Wrong QT review policy' unless plan.fetch('policy') == POLICY
          ids = LocalEvalArtifact.read_jsonl(File.join(audit + '-qtclustering', 'final/decisions.jsonl'))
            .select { |row| row['adjudication_verdict'] }.map { |row| row.fetch('program_id') }.sort
        else
          ids = LocalEvalArtifact.read_jsonl(File.join(source, 'inventory.jsonl')).map { |row| row.fetch('id') }.sort
        end
        raise 'Review coverage differs' unless results.size == expected.fetch('responses') && results.map { |row| row.fetch('program_id') }.sort == ids
        jsonl.call("#{destination}/results.jsonl", results)
        prior_attempts_path = File.join(batch, destination, 'attempts.jsonl')
        prior_attempts = File.file?(prior_attempts_path) ? LocalEvalArtifact.read_jsonl(prior_attempts_path) : []
        prior_by_key = prior_attempts.to_h { |row| [[row.fetch('program_id'), row.fetch('attempt')], row] }
        raise 'Duplicate previously exported attempts' unless prior_by_key.size == prior_attempts.size
        attempts = Dir[File.join(source, 'logs/*/attempt-*/metadata.yaml')].sort.map do |path|
          metadata = LocalEvalArtifact.load_yaml(path)
          metadata = preserve_native_attempt_diagnostics(metadata,
            prior_by_key[[metadata.fetch('program_id'), metadata.fetch('attempt')]])
          events = LocalEvalArtifact.read_jsonl(File.join(File.dirname(path), 'events.jsonl'))
          raise 'Non-static review event' if events.any? { |event| event['item'] && !%w[agent_message reasoning error].include?(event.fetch('item')['type']) }
          errors = events.filter_map { |event| event['message'] if event['type'] == 'error' }.uniq
          metadata['exported_transport_errors'] = errors unless errors.empty?
          metadata
        end
        raise 'Attempt coverage differs' unless attempts.size == expected.fetch('retained_attempts') && expected.fetch('prohibited_tool_events').zero?
        jsonl.call("#{destination}/attempts.jsonl", attempts)
        %w[final recovery final-before-platform-reconciliation].each do |directory|
          Dir[File.join(source, directory, '*')].sort.each do |path|
            copy.call(path, "#{destination}/#{directory}/#{File.basename(path)}") if File.file?(path)
          end
        end
      end
      decisions = {}
      inputs = report.fetch('decision_roots').map do |source|
        relative = "timing-audit/#{stage_names.fetch(source)}/final/decisions.jsonl"
        LocalEvalArtifact.read_jsonl(File.join(batch, relative)).each do |row|
          id = row.fetch('program_id')
          raise 'Overlay source changed' if decisions[id] && decisions.fetch(id).fetch('source_digest') != row.fetch('source_digest')
          decisions[id] = row
        end
        { 'path' => relative, 'sha256' => LocalEvalArtifact.sha256(File.join(batch, relative)) }
      end
      raise 'Resolved audit coverage differs' unless decisions.keys.sort == expected_ids
      counts = decisions.values.map { |row| row.fetch('final_verdict') }.tally
      raise 'Resolved audit counts differ' unless counts == report.fetch('verdicts')
      raise 'Unresolved review conditions' unless decisions.values.all? { |row| row.fetch('timing_review_required') == false }
      correction_ids = decisions.values.select { |row| row.fetch('timing_fix_required') }.map { |row| row.fetch('program_id') }.sort
      json.call('timing-audit/resolved-selection.json', {
        'schema_version' => 1, 'source_commit' => ORIGINAL, 'record_count' => decisions.size,
        'ordered_decisions' => inputs, 'verdict_counts' => counts, 'correction_ids' => correction_ids,
        'policy' => 'Same-source QT, user-approved fixed-size Black-Scholes setup policy, and targeted cross-review decisions overlay the general audit in the recorded order. Every earlier finding is retained.'
      })
      write.call('timing-audit/conditional-decisions.jsonl', '')
      selected.call(evaluation, 'completion', %w[audit-completion-review.json verify-audit-completion.rb review-policy.json
        prepare-review-policy.rb verify-primary-pilot.rb audit-pilot-driver.rb audit-full-driver-policy.rb
        audit-pilot-launch.json audit-full-launch.json timing-platform-context.txt
        pilot-source-quality-review.json record-pilot-source-check.rb qt-pilot-source-quality-review.json accept-static-pilots.rb
        audit-citation-normalization.json audit-citation-normalization.rb test-audit-citation-normalization.rb
        normalize-one-audit-citation.rb audit-format-retry.json audit-format-retry-launch.json
        audit-format-recovery-resume-launch.json resume-audit-after-citation-normalization.rb
        static-review-export-preparation.json prepare-static-review-export-evidence.rb])
      selected.call(evaluation, 'completion', %w[platform-timing-reconciliation.json platform-followup-preparation.json
        verify-audit-before-platform.rb review-cholesky-platform.rb finalize-cholesky-platform.rb])
      platform_proof = File.join(evaluation, 'cholesky-mpi-r2-topology-context')
      selected.call(platform_proof, 'timing-audit/platform-sol61/target-platform-proof',
        %w[preprocessing-proof.json preprocessed-makeNode.txt mpi-header-excerpt.txt benchmark-profile-excerpt.txt
          native-build-flags.make prepare-cholesky-topology-context.rb]) if report['platform_reconciliation']
      Gpt62GenerationEvidence.retain_policy_history!(evaluation: evaluation, audit: audit, copy: copy, jsonl: jsonl)
      summary = JSON.parse(File.read(File.join(batch, 'summary.json')))
      summary['timing_audit_final_verdicts'] = counts
      report.fetch('reviews').each { |row| summary.fetch('timing_audit_records')[stage_names.fetch(row.fetch('root'))] = row.fetch('responses') }
      summary['timing_audit_selection'] = 'timing-audit/resolved-selection.json'
      summary['unique_timing_audited_programs'] = decisions.size
      json.call('summary.json', summary)
      puts "Retained #{report.fetch('reviews').size} audit stages, #{decisions.size} resolved programs, #{correction_ids.size} corrections."
      return
    end

    raise 'Export aggregate first' unless File.file?(File.join(batch, 'aggregate/export.json'))
    rows = CSV.read(File.join(batch, 'aggregate/aggregate_results.csv'), headers: true).to_h do |row|
      ["#{row['benchmark']}_#{row['model']}_#{row['par_type']}_r#{row['run']}", row]
    end
    generation = Gpt62GenerationEvidence.retain(campaign: campaign, root: root, rows: rows,
      copy: copy, write: write, json: json, jsonl: jsonl)
    selected.call(evaluation, 'completion', %w[campaign.json review-tooling.json timing-platform-context.txt
      validation-launch-gate.json validation-completion-review.json correction-pilot-gate.json correction-pilot-diff-check.json
      record-correction-pilot-check.rb correction-commit.json correction-template-context.json correction-driver-template-reuse.json
      revalidation-completion-review.json benchmark-canary-gate.json benchmark-completion-review.json benchmark-progress.json
      verify-validation-completion.rb verify-correction-pilot.rb verify-revalidation-completion.rb verify-benchmark-records.rb
      commit-corrections.rb benchmark-driver.rb prepare-release-export.rb export-completed-batch.rb
      test_gpt62_generation_evidence.rb generation-export-tests.log release-export-tests.log
      release-export-check.json verify-release-export-preparation.rb release-export-preparation.json
      prepare-gpt62-exporters.rb benchmark-export.rb])
    summary = JSON.parse(File.read(File.join(batch, 'summary.json')))
    summary['benchmarking_performed'] = true
    summary.fetch('timing_corrections')['benchmarking_performed'] = true if summary['timing_corrections']
    summary['generation'] = generation
    json.call('summary.json', summary)
    puts 'Retained 440 Astra/Sol 6.2 observations, exact accounting, selected Standard pricing and compact request evidence.'
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} audit|complete HOME" unless ARGV.size == 2 && %w[audit complete].include?(ARGV.first)
  Gpt62Supplement.run(root: File.expand_path('..', __dir__), home: File.expand_path(ARGV.last), phase: ARGV.first)
end
