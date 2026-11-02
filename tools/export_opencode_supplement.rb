#!/usr/bin/env ruby
# frozen_string_literal: true

# Compact OpenCode-specific evidence. Established exporters retain native
# validation, timing corrections and measurements; no generated programs run here.
require_relative "artifact_common"
require "open3"
require_relative "../method/external-validation/tools/timing_audit/lib/external_validation_exclusions"

module OpenCodeSupplement
  DEFAULT_BATCH = "20261017-192226"
  CAMPAIGNS = {
    DEFAULT_BATCH => {
      "suffix" => "sol61-opencode-medium", "audit_id" => "20261018-sol61-opencode",
      "original" => "352c09d57e14ef93744aa8cc741ff52884079e5f"
    }.freeze,
    "20261018-224015" => {
      "suffix" => "luna6-opencode-medium", "audit_id" => "20261019-luna6-opencode",
      "original" => "fd64978a13b9a4f3ac6a5e368972316d0c159aa1"
    }.freeze,
    "20261019-134042" => {
      "suffix" => "deepseek41-flash-opencode-high", "audit_id" => "20261023-deepseek41-opencode",
      "original" => "40ad0bc6da259d4584e75b8f23f43c77e9751b24"
    }.freeze,
    "20261025-170040" => {
      "suffix" => "haiku55-opencode-medium", "audit_id" => "20261028-haiku55-opencode",
      "original" => "24648e59045c3e8d7280119627a7bccde1da4f2f"
    }.freeze,
    "20261025-170121" => {
      "suffix" => "beam10-opencode-medium", "audit_id" => "20261030-beam10-opencode",
      "original" => "74652eee82e2473660a7e75f3ad5d77fd0e3759c",
      "context_summary" => "request-context-verification.json",
      "audit_report" => "audit-completion-final-replica-review.json",
      "external_validation_registry" => "validation-supplements/20261101-unstructured-boundary/external-validation-exclusions.json",
      "supplemental_audits" => %w[supplemental-communication-20261031 replicated-work-luna-20261101
        replicated-work-extra-luna-20261101 replicated-work-sol61-20261101 replicated-broadcast-luna-20261101].freeze,
      "decision_overlays" => %w[replicated-work-final-20261101 replicated-broadcast-final-20261101].freeze,
      "replica_selection" => "final-replica-correction-selection-20261101.json"
    }.freeze
  }.freeze
  POLICY = "luna_first_uncertainty_or_disagreement_v1"
  module_function

  def configuration(batch_id)
    CAMPAIGNS.fetch(batch_id) { raise "Unknown OpenCode campaign: #{batch_id}" }
  end

  def checked_method_bytes(files)
    files.to_h do |name, digest|
      raise "Unsafe generation method path: #{name}" if Pathname.new(name).absolute? || name.split('/').include?('..')
      bytes = yield(name)
      raise "Generation method changed: #{name}" unless Digest::SHA256.hexdigest(bytes) == digest
      [name, bytes]
    end
  end

  def audit_scope(records)
    records.select do |row|
      info = row.fetch("metadata")
      LocalEvalArtifact::VALIDATION_STAGES.all? { |stage| info.fetch("stages").fetch(stage) == true } &&
        (%w[mpi hybrid].include?(info.fetch("par_type")) || info.fetch("benchmark") == "qtclustering")
    end.map { |row| row.fetch("id") }.sort
  end

  def verify_reference_boundary!(source, manifest)
    path = File.join(source, 'sequential-reference.cpp')
    return unless File.file?(path)
    reference = manifest.fetch('reference_boundary')
    raise 'Unpinned sequential reference revision' unless reference.fetch('commit').match?(/\A[0-9a-f]{40}\z/)
    relative = reference.fetch('path')
    raise 'Unsafe sequential reference path' if relative.empty? || Pathname.new(relative).absolute? || relative.split('/').include?('..')
    raise 'Sequential reference digest changed' unless LocalEvalArtifact.sha256(path) == reference.fetch('sha256')
    # The exact reference is reconstructable from the retained commit/path/digest;
    # do not duplicate its source file in the curated scientific artifact.
  end

  def run(root:, home:, phase:, batch_id: DEFAULT_BATCH, selection: nil)
    raise "Unknown supplement phase" unless %w[audit complete].include?(phase)
    config = configuration(batch_id).merge(selection ? selection.slice('original', 'audit_id') : {})
    original = config.fetch("original")
    relative_base = selection ? selection.fetch('evidence_root') : "batches/#{batch_id}"
    raise 'Unsafe export destination' if Pathname.new(relative_base).absolute? || relative_base.split('/').include?('..')
    batch = File.join(root, relative_base)
    campaign = File.join(home, "llm_para_campaigns/#{batch_id}-#{config.fetch('suffix')}")
    evaluation = selection ? selection.fetch('evaluation') : File.join(campaign, "evaluation")
    expected_count = selection ? selection.fetch('ids').size : 220
    audit = File.join(home, "llm_timing_audit", config.fetch("audit_id"))
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
    report_name = selection ? 'audit-export-binding.json' : config.fetch('audit_report', 'audit-completion-review.json')
    report = JSON.parse(File.read(File.join(evaluation, report_name)))
    expected_ids = audit_scope(LocalEvalArtifact.read_jsonl(File.join(batch, "validation/records.jsonl")))
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
      additional_stages = %w[qtclustering qtclustering-sol61] + config.fetch('supplemental_audits', [])
      additional_stages.each do |suffix|
        source = "#{audit}-#{suffix}"
        destination = "timing-audit/#{suffix}"
        expected = report.fetch("reviews").find { |row| row.fetch("root") == source }
        raise "Unbound additional audit manifest" unless expected && LocalEvalArtifact.sha256(File.join(source, "manifest.yaml")) == expected.fetch("manifest_sha256")
        selected.call(source, destination, %w[manifest.yaml inventory.jsonl excluded.jsonl trial-ids.txt
          prompt-template.txt result-schema.json runner-snapshot.rb static-evidence-snapshot.rb preparer-snapshot.rb
          summary-full.jsonl summary-full.csv summary-trial.jsonl summary-trial.csv review-guidance.txt platform-context.txt
          comparison.jsonl comparison.csv operational-provenance.json review-policy-snapshot.rb active-review-policy-full.rb
          adjudication-plan-full.json adjudication-selection.jsonl supplemental-selection.jsonl reused-reviews.json pilot-review.json
          replicated-work-timing-contract.txt parent-prompt-template.txt])
        verify_reference_boundary!(source, LocalEvalArtifact.load_yaml(File.join(source, 'manifest.yaml')))
        results = Dir[File.join(source, "results/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
        ids = if suffix == "qtclustering-sol61"
          plan = JSON.parse(File.read(File.join(source, "adjudication-plan-full.json")))
          raise "Wrong QT adjudication policy" unless plan.fetch("policy") == POLICY
          LocalEvalArtifact.read_jsonl(File.join("#{audit}-qtclustering", "final/decisions.jsonl"))
            .select { |row| row["adjudication_verdict"] }.map { |row| row.fetch("program_id") }.sort
        else
          LocalEvalArtifact.read_jsonl(File.join(source, "inventory.jsonl")).map { |row| row.fetch("id") }.sort
        end
        raise "Additional audit result scope differs" unless results.size == expected.fetch("responses") && results.map { |row| row.fetch("program_id") }.sort == ids
        jsonl.call("#{destination}/results.jsonl", results)
        attempts = Dir[File.join(source, "logs/*/attempt-*/metadata.yaml")].sort.map do |path|
          metadata = LocalEvalArtifact.load_yaml(path)
          events = LocalEvalArtifact.read_jsonl(File.join(File.dirname(path), "events.jsonl"))
          raise "Non-static additional audit event" if events.any? { |event| event["item"] && !%w[agent_message reasoning error].include?(event.fetch("item")["type"]) }
          errors = events.filter_map { |event| event["message"] if event["type"] == "error" }.uniq
          metadata["exported_transport_errors"] = errors unless errors.empty?
          metadata
        end
        raise "Additional audit attempt scope differs" unless attempts.size == expected.fetch("retained_attempts") && expected.fetch("prohibited_tool_events").zero?
        jsonl.call("#{destination}/attempts.jsonl", attempts)
        Dir[File.join(source, "final/*")].sort.each { |path| copy.call(path, "#{destination}/final/#{File.basename(path)}") if File.file?(path) }
        if config.fetch('supplemental_audits', []).include?(suffix)
          Dir[File.join(source, "prior-final/*")].sort.each { |path| copy.call(path, "#{destination}/prior-final/#{File.basename(path)}") if File.file?(path) }
          Dir[File.join(source, "reused-parent/*")].sort.each { |path| copy.call(path, "#{destination}/reused-parent/#{File.basename(path)}") if File.file?(path) }
        end
      end
      decision_overlays = config.fetch('decision_overlays', [])
      decision_overlays.each do |stage|
        source = "#{audit}-#{stage}"
        destination = "timing-audit/#{stage}"
        %w[manifest.yaml inventory.jsonl final/metadata.yaml final/decisions.jsonl].each do |name|
          path = File.join(source, name)
          raise "Unbound decision overlay: #{name}" unless report.fetch("input_sha256")[path] == LocalEvalArtifact.sha256(path)
        end
        manifest = LocalEvalArtifact.load_yaml(File.join(source, "manifest.yaml"))
        raise "Decision overlay source differs" unless manifest.dig("generated_source", "commit") == original
        selected.call(source, destination, %w[manifest.yaml inventory.jsonl user-decision.json replicated-work-timing-contract.txt])
        Dir[File.join(source, "final/*")].sort.each { |path| copy.call(path, "#{destination}/final/#{File.basename(path)}") if File.file?(path) }
      end
      decisions = {}
      inputs = (%w[primary qtclustering] + decision_overlays).map do |stage|
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
      external_selection = nil
      if config["external_validation_registry"]
        registry = ExternalValidationExclusions.new(File.join(root, config.fetch("external_validation_registry")))
        excluded = registry.ids_for(source_commit: original, ids: correction_ids)
        copy.call(registry.path, "external-validation/exclusions.json")
        external_selection = { "path" => "external-validation/exclusions.json", "sha256" => registry.digest, "excluded_ids" => excluded }
        correction_ids -= excluded
      end
      raise "Unresolved audit conditions" unless decisions.values.all? { |row| row.fetch("timing_review_required") == false }
      json.call("timing-audit/resolved-selection.json", {
        "schema_version" => 1, "source_commit" => original, "record_count" => decisions.size,
        "ordered_decisions" => inputs, "verdict_counts" => counts, "correction_ids" => correction_ids,
        "external_validation_exclusions" => external_selection,
        "policy" => "Later source-pinned decisions overlay the general MPI/hybrid audit, including the all-backend QT boundary and any explicit contract adjudications. All prior review evidence is retained."
      })
      write.call("timing-audit/conditional-decisions.jsonl", "")
      selected.call(evaluation, "completion", %w[audit-completion-review.json verify-audit-completion.rb review-policy.json
        prepare-review-policy.rb verify-primary-pilot.rb audit-pilot-driver.rb audit-full-driver-policy.rb
        audit-pilot-launch.json audit-full-launch.json timing-platform-context.txt
        paced-audit-driver.rb review-request-pacing.rb test-review-request-pacing.rb launch-paced-audit.rb
        audit-pilot-paced-launch.json audit-pilot-paced-activation.json audit-pilot-paced-progress.json
        audit-full-paced-launch.json audit-full-paced-activation.json audit-full-paced-progress.json
        audit-pilot-paced-launcher.rb audit-full-paced-launcher.rb audit-pacing-tests.json audit-pacing-tests.log
        audit-pilot-citation-recovery.json audit-pilot-citation-activation.json retry-pilot-citation-syntax.rb
        audit-fable-yield-20261030.json checkpoint-fable-yield.rb
        audit-full-resume-20261031-launch.json audit-full-resume-20261031-activation.json
        audit-full-resume-20261031-progress.json paced-audit-resume-20261031.rb resume-paced-audit-20261031.rb
        audit-completion-supplemental-review.json verify-audit-supplemental-completion.rb
        finalize-audit-supplemental-20261031.rb audit-supplemental-20261031.rb
        audit-supplemental-20261031-launch.json audit-supplemental-20261031-activation.json
        audit-supplemental-20261031-progress.json audit-supplemental-context-20261031.txt
        audit-supplemental-focus-20261031.txt audit-supplemental-selection-20261031.jsonl
        extend-audit-supplemental-20261031.rb audit-supplemental-communication-selection-20261031.jsonl
        audit-supplemental-communication-20261031-launch.json audit-supplemental-communication-20261031-activation.json
        audit-supplemental-communication-20261031-progress.json
        audit-pilot-resume-1.json audit-pilot-resume-2.json resume-audit-pilot.rb resume-audit-pilot-2.rb])
      selected.call(evaluation, "completion", %w[replicated-work-user-decision-20261101.json
        replicated-work-timing-contract-20261101.txt replicated-work-selection-20261101.jsonl
        replicated-work-review-launch-20261101.json replicated-work-review-progress-20261101.json
        replicated-work-extra-review-launch-20261101.json replicated-work-extra-review-progress-20261101.json
        replicated-work-sol61-review-launch-20261101.json replicated-work-sol61-review-progress-20261101.json
        review-replicated-work-20261101.rb review-replicated-work-extra-20261101.rb review-replicated-work-sol61-20261101.rb
        audit-completion-replicated-work-review.json replicated-work-correction-selection-20261101.json
        reconcile-replicated-work-20261101.rb verified-replicated-work.rb correction-build-scope-review-20261101.json])
      selected.call(evaluation, "completion", %w[replicated-broadcast-review-launch-20261101.json
        replicated-broadcast-review-progress-20261101.json review-replicated-broadcast-20261101.rb
        audit-completion-final-replica-review.json final-replica-correction-selection-20261101.json
        finalize-replica-selection-20261101.rb verified-final-replica-selection.rb final-replica-preparation-20261101.json])
      unless decision_overlays.empty?
        reconciliation = JSON.parse(File.read(File.join(evaluation, config.fetch("replica_selection"))))
        raise "Reconciled corrections differ" unless reconciliation.fetch("correction_ids") == correction_ids
        omitted = reconciliation.fetch("accepted_unchanged_replica_ids").sort
        parent = reconciliation.fetch("prior_proposal_root")
        expected_parent = File.join(home, "llm_timing_fixes", config.fetch("audit_id") + "-proposals")
        raise "Unexpected superseded proposal root" unless File.realpath(parent) == File.realpath(expected_parent)
        retained = omitted.map do |id|
          path = File.join(parent, "proposals", "#{id}.json")
          raise "Superseded proposal changed" unless report.fetch("input_sha256")[path] == LocalEvalArtifact.sha256(path)
          JSON.parse(File.read(path))
        end
        jsonl.call("timing-audit/superseded-replica-proposals/proposals.jsonl", retained)
        inventory = LocalEvalArtifact.read_jsonl(File.join(parent, "inventory.jsonl")).select { |row| omitted.include?(row.fetch("id")) }
        raise "Superseded proposal coverage differs" unless inventory.map { |row| row.fetch("id") }.sort == omitted
        jsonl.call("timing-audit/superseded-replica-proposals/inventory.jsonl", inventory)
        attempts = omitted.flat_map do |id|
          Dir[File.join(parent, "logs", id, "attempt-*/metadata.yaml")].sort.map { |path| LocalEvalArtifact.load_yaml(path) }
        end
        jsonl.call("timing-audit/superseded-replica-proposals/attempts.jsonl", attempts)
        json.call("timing-audit/superseded-replica-proposals/disposition.json", {
          "ids" => omitted, "source_commit" => original, "applied" => false,
          "decision_overlay" => "timing-audit/#{decision_overlays.last}/final/decisions.jsonl",
          "policy" => "Prior proposals retained as historical evidence only; complete local replica timing was accepted, so these source edits were not applied."
        })
      end
      citation_recovery = File.join(evaluation, 'audit-pilot-citation-recovery.json')
      if File.file?(citation_recovery)
        amendment = JSON.parse(File.read(citation_recovery))
        source = File.join(audit, 'citation-syntax-amendment')
        selected.call(source, 'timing-audit/primary/citation-syntax-amendment', %w[manifest.yaml result-schema.json audit-pilot-citation-recovery.json])
        failed_events = File.join(File.dirname(amendment.fetch('formatting_attempt').fetch('metadata_path')), 'events.jsonl')
        raise 'Rejected citation response changed' unless LocalEvalArtifact.sha256(failed_events) == amendment.dig('formatting_attempt', 'events_sha256')
        copy.call(failed_events, 'timing-audit/primary/citation-syntax-amendment/rejected-events.jsonl')
      end
      summary = JSON.parse(File.read(File.join(batch, "summary.json")))
      summary["timing_audit_final_verdicts"] = counts
      additional_stages.each do |suffix|
        summary.fetch("timing_audit_records")[suffix] = report.fetch("reviews")
          .find { |row| row.fetch("root") == "#{audit}-#{suffix}" }.fetch("responses")
      end
      summary["timing_audit_selection"] = "timing-audit/resolved-selection.json"
      summary["unique_timing_audited_programs"] = decisions.size
      summary["timing_audit_operator_adjudications"] = report.fetch("operator_adjudications", 0) unless decision_overlays.empty?
      json.call("summary.json", summary)
      puts "Retained #{3 + additional_stages.size} audit stages, #{decisions.size} resolved programs, #{correction_ids.size} timing corrections."
      return
    end

    raise "Export native aggregate first" unless File.file?(File.join(batch, "aggregate/export.json"))
    if selection
      selected.call(campaign, 'generation', %w[campaign.json])
      amendment_root = File.dirname(evaluation)
      selected.call(amendment_root, 'generation', %w[run-ids.txt completion.json launch.json])
      selected.call(amendment_root, 'generation/supervision', %w[run.rb monitor.rb prepare.rb])
      selected.call(evaluation, 'generation', %w[source-retention-push.json])
    else
      selected.call(campaign, "generation", %w[campaign.json run-ids.txt preflight-ids.txt preflight-gate.json
        preflight-review.json completion.json completion-audit.json launch.json source-retention-push.json
        access-review.json access-review-completed.json])
      selected.call(campaign, "generation/supervision", %w[run.rb monitor.rb launch-full.rb review-preflight.rb
        verify-access-preserved.rb audit-completion.rb])
    end
    reusable = {}
    LocalEvalArtifact.regular_files(root).each do |path|
      relative = LocalEvalArtifact.relative_path(root, path)
      next unless relative.start_with?("method/") || relative.match?(%r{\Abatches/[^/]+/(?:method|generation/(?:method|runtime-method)|timing-corrections/method|benchmark/method)/})
      reusable[LocalEvalArtifact.sha256(path)] ||= relative
    end
    manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
    raise "Generation campaign identity differs" unless manifest.fetch("campaign_id") == batch_id
    original_manifest = manifest
    previous_manifest = if manifest['filesystem_amendment']
      raise 'Filesystem amendment needs explicit export selection' unless selection &&
        manifest.fetch('filesystem_amendment').fetch('affected_observations').sort == selection.fetch('ids').sort
      JSON.parse(File.read(File.join(manifest.fetch('filesystem_amendment').fetch('path'), 'before/campaign.json')))
    else
      manifest
    end
    amendment_root = nil
    amendment = nil
    if manifest["runtime_amendment"]
      amendment_root = manifest.fetch("runtime_amendment").fetch("path")
      amendment = JSON.parse(File.read(File.join(amendment_root, "amendment.json")))
      original_manifest = JSON.parse(File.read(File.join(amendment_root, "campaign-0-before.json")))
      revision = previous_manifest.fetch("runtime_source_commit")
      raise "Generation runtime amendment differs" unless amendment.fetch("source_commit") == revision &&
        revision.match?(/\A[0-9a-f]{40}\z/) && amendment.fetch("replacement_batch") == batch_id &&
        amendment.fetch("affected_observations").sort == manifest.fetch("runtime_amendment").fetch("affected_observations").sort &&
        original_manifest.fetch("campaign_id") == batch_id && original_manifest.fetch("source_commit") == manifest.fetch("source_commit") &&
        original_manifest.fetch("source_commit") == manifest.fetch("runtime_amendment").fetch("original_source_commit")
    end
    store_methods = lambda do |files, destination|
      files.to_h do |name, bytes|
        digest = Digest::SHA256.hexdigest(bytes)
        relative = reusable[digest]
        unless relative
          stored = "#{destination}/#{name.gsub('/bin/', '/commands/')}"
          write.call(stored, bytes)
          relative = "#{relative_base}/#{stored}"
          reusable[digest] = relative
        end
        [name, relative]
      end
    end
    original_bytes = checked_method_bytes(original_manifest.fetch("files")) do |name|
      File.binread(File.join(campaign, "method", name))
    end
    layout = store_methods.call(original_bytes, "generation/method")
    if amendment
      json.call("generation/original-method-layout.json", {
        "source_commit" => original_manifest.fetch("source_commit"), "files" => layout
      })
      revision = manifest.fetch("runtime_source_commit")
      repository = File.join(home, "llm_eval/experiment")
      runtime_bytes = checked_method_bytes(manifest.fetch("files")) do |name|
        bytes, status = Open3.capture2("git", "-C", repository, "show", "#{revision}:#{name}")
        raise "Missing generation runtime source: #{name}" unless status.success?
        bytes
      end
      layout = store_methods.call(runtime_bytes, "generation/runtime-method")
      runtime_layout = layout.to_h { |name, relative| [name, { "path" => relative, "sha256" => manifest.fetch("files").fetch(name) }] }
      json.call("generation/runtime-method-layout.json", { "source_commit" => revision, "files" => runtime_layout })
      selected.call(amendment_root, "generation/output-limit-amendment", %w[amendment.json resume.json
        campaign-0-before.json unchanged-observations.json original-attempt-file-hashes.json
        inspect.rb amend.rb resume.rb native-configuration-checks.log regression-tests.log])
    end
    if manifest['filesystem_amendment']
      revision = previous_manifest.fetch('runtime_source_commit')
      previous_bytes = checked_method_bytes(previous_manifest.fetch('files')) do |name|
        bytes, status = Open3.capture2('git', '-C', File.join(home, 'llm_eval/experiment'), 'show', "#{revision}:#{name}")
        raise "Missing previous generation method: #{name}" unless status.success?
        bytes
      end
      prior_layout = store_methods.call(previous_bytes, 'generation/pre-isolation-method')
      json.call('generation/pre-isolation-method-layout.json', { 'source_commit' => revision, 'files' => prior_layout })
      json.call('generation/filesystem-amendment/before-campaign.json', previous_manifest)
      amendment_root = manifest.fetch('filesystem_amendment').fetch('path')
      selected.call(amendment_root, 'generation/filesystem-amendment', %w[amendment.json run-ids.txt completion.json
        replacement-access-review.json replacement-marker-scan.json.gz unchanged-observations.json unchanged-files.json
        superseded-files.json prepare.rb run-replacements.rb audit-replacements.rb retain-replacement-access-review.rb
        controller-check-fix.json controller-check-stop.json resume-after-check-fix.rb])
      selected.call(File.join(campaign, 'evaluation/contamination-audit-20261023'),
        'generation/filesystem-amendment/original-access-audit', %w[review.json marker-scan.json.gz
        definite-rerun-ids.txt evaluator-only-ids.txt retain-review.rb generation-isolation-preflight-20261023.log
        generation-isolation-regressions-20261023.log generation-isolation-systemd-regressions-20261023.log])
      json.call('generation/filesystem-amendment/binding.json', {
        'schema_version' => 1, 'ids' => selection.fetch('ids').sort,
        'previous_source_commit' => revision, 'source_commit' => manifest.fetch('runtime_source_commit'),
        'policy' => manifest.fetch('generation_filesystem_policy'),
        'before_campaign_sha256' => LocalEvalArtifact.sha256(File.join(batch, 'generation/filesystem-amendment/before-campaign.json'))
      })
    end
    json.call("generation/method-layout.json", layout)
    observations = Dir[File.join(campaign, "observations/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
    observations.select! { |row| selection.fetch('ids').include?(row.fetch('id')) } if selection
    rows = CSV.read(File.join(batch, "aggregate/aggregate_results.csv"), headers: true).to_h do |row|
      ["#{row['benchmark']}_#{row['model']}_#{row['par_type']}_r#{row['run']}", row]
    end
    raise "Generation scope differs" unless observations.size == expected_count && observations.map { |row| row.fetch("id") }.sort == rows.keys.sort
    require_relative "current_release"
    verifier = CurrentRelease.allocate
    verifier.instance_variable_set(:@root, root)
    observations.select { |row| row.fetch("outcome") == "generation_model_terminated" }.each do |row|
      id = row.fetch("id")
      raise "Unsafe terminated run ID" unless id.match?(/\A[a-zA-Z0-9_.-]+\z/)
      source = File.join(home, "llm_para_experiments", batch_id, id, "generation-termination.txt")
      raise "Termination receipt changed" unless LocalEvalArtifact.sha256(source) == row.fetch("termination_record_sha256")
      copy.call(source, "generation/terminations/#{id}.json")
    end
    verifier.verify_generation_observations!({ "id" => batch_id, "evidence_root" => relative_base, "generation_harness" => "opencode" }, observations, rows)
    shared = observations.map { |row| row.slice("resolved_model", "tools") }.uniq
    raise "Multiple effective OpenCode configurations" unless shared.size == 1
    json.call("generation/common-configuration.json", shared.first)
    common_sha = LocalEvalArtifact.sha256(File.join(batch, "generation/common-configuration.json"))
    jsonl.call("generation/observations.jsonl", observations.map { |row| row.except("resolved_model", "tools").merge("common_configuration_sha256" => common_sha) })
    cleanup = Dir[File.join(campaign, "cleanup/*.json")].sort.map { |path| JSON.parse(File.read(path)) }
    cleanup.select! { |row| selection.fetch('ids').include?(row.fetch('id')) } if selection
    raise "Cleanup coverage differs" unless cleanup.map { |row| row.fetch("id") }.sort == rows.keys.sort && cleanup.all? { |row| row.fetch("verified_empty") }
    jsonl.call("generation/cleanup.jsonl", cleanup)
    (selection ? [] : %w[pilot-audit-visibility pilot-postprocessing]).each do |incident|
      selected.call(File.join(campaign, "incidents", incident), "generation/incidents/#{incident}", %w[receipt.json])
    end
    if batch_id == "20261019-134042" && !selection
      %w[20261020-agent-self-termination 20261021-output-token-limit 20261021-initial-503
         20261022-agent-self-termination 20261023-agent-self-termination].each do |incident|
        selected.call(File.join(campaign, "incidents", incident), "generation/incidents/#{incident}",
          %w[incident.json recovery.json resume.json prepared.json cleanup.json retain.rb resume.rb retain-and-retry.rb])
      end
    end
    if batch_id == "20261025-170121" && !selection
      selected.call(File.join(campaign, 'incidents/20261029-prompt-rendering-failure'),
        'generation/incidents/20261029-prompt-rendering-failure', %w[review.json decision.json retained-observation.json
          admission-amendment.json regression-tests.log resume.json record-adjudication.rb resume.rb retain_opencode_protocol_failure.rb])
    end
    pricing = selection ? selection.fetch('pricing') : File.join(campaign, "pricing")
    context_summary = config.fetch("context_summary", "request-context-summary.json")
    context = JSON.parse(File.read(File.join(pricing, context_summary)))
    context_records = nil
    if context['pricing_context_policy'] == 'request_input_above_100000'
      context_path = File.join(pricing, 'context-usage.jsonl')
      raise 'OpenCode request-context evidence changed' unless LocalEvalArtifact.sha256(context_path) == context.fetch('context_usage_sha256')
      context_records = LocalEvalArtifact.read_jsonl(context_path)
    end
    verifier.verify_opencode_context!({ "id" => batch_id, "source_commit" => original }, observations, context, context_records: context_records)
    selected.call(pricing, "generation/pricing", %w[pricing-reference.json context-usage.jsonl retain-pricing-context.rb retain-pricing-reference.rb retain-release-context.rb
      pricing-refresh.json deepseek-refresh-current-pricing-20261024.rb current-context-review.json deepseek-bind-current-context-20261024.rb])
    copy.call(File.join(pricing, context_summary), "generation/pricing/request-context-summary.json")
    if context_summary != "request-context-summary.json"
      source_summary = File.join(pricing, "request-context-summary.json")
      raise 'Original request summary changed' unless LocalEvalArtifact.sha256(source_summary) == context.fetch('source_summary_sha256')
      copy.call(source_summary, "generation/pricing/source-request-context-summary.json")
    end
    selected.call(evaluation, "completion", %w[campaign.json validation-launch-gate.json validation-completion-review.json
      scientific-followup-hold.json scientific-followup-resolution.json record-unstructured-halo-concern.rb verified-external-validation.rb
      correction-pilot-gate.json correction-commit.json source-correction-push.json revalidation-completion-review.json
      revalidation-output-order-review.json record-revalidation-output-order.rb
      validation-failure-review.json record-validation-failure-review.rb aggregate-export-amendment.json
      apply-aggregate-export-amendment.rb
      benchmark-canary-gate.json benchmark-completion-review.json benchmark-progress.json
      canary-program-failure-review.json review-canary-failure.rb verify-benchmark-records-v2.rb launch-measurement-stage-v5.rb
      replica-output-contract-decision-20261102.json
      benchmark-resume-launch.json benchmark-stopped-before-measurement-progress.json
      resume-benchmark-after-canary-review.rb benchmark-orchestration-v2.rb benchmark-driver-v3.rb
      benchmark-resume-launch-v2.json benchmark-stopped-runner-provenance-progress.json
      canary-runner-amendment.json prepare-canary-runner-amendment.rb verify-canary-runner-amendment.rb
      resume-benchmark-after-canary-review-v2.rb benchmark-orchestration-v3.rb benchmark-driver-v4.rb
      verify-validation-completion.rb verify-correction-pilot.rb verify-revalidation-completion.rb verify-benchmark-records.rb
      commit-corrections.rb benchmark-driver.rb canary-driver.rb correction-pilot-driver.rb correction-full-driver.rb
      revalidation-driver.rb validation-launch.json correction-pilot-launch.json correction-full-launch.json
      correction-pilot-recovery-launch.json correction-pilot-recovery-progress.json
      resume-correction-pilot-driver.rb launch-correction-pilot-recovery.rb
      paced-correction-driver.rb launch-paced-corrections.rb
      correction-request-pacing.rb test-correction-request-pacing.rb
      correction-pilot-paced-launch.json correction-pilot-paced-activation.json correction-pilot-paced-progress.json
      correction-full-paced-launch.json correction-full-paced-activation.json correction-full-paced-progress.json
      correction-pilot-paced-startup-recovery.json retry-paced-startup.rb launch-paced-corrections-current.rb
      revalidation-launch.json canary-launch.json benchmark-launch.json benchmark-driver-template-reuse.json
      prepare-benchmark-drivers.rb prepare-corrected-checkout.rb corrected-checkout.json correction-driver-template-reuse.json correction-template-context.json
      benchmark-export-template-reuse.json prepare-release-export.rb export-completed-batch.rb
      correction-revision-1.json correction-revision-feedback.json correction-revision-launch.json
      correction-revision-driver.rb reuse-unchanged-correction-reviews.rb
      correction-followup-rebinding.json prepare-revised-correction-followup.rb])
    selected.call(evaluation, "completion", %w[revalidation-boundary-driver.rb verify-revalidation-boundary.rb
      launch-measurement-stage-v2.rb external-revalidation-completion.json
      export-completed-batch-v2.rb prepare-release-export-v2.rb])
    selected.call(evaluation, "completion", %w[correction-resumed-launch-20261101.json correction-resumed-progress-20261101.json
      correction-resumed-paced-progress-20261101.json resume-corrections-20261101.rb
      timing-fix-proposal-reuse-frozen.rb timing-fix-review-reuse-frozen.rb
      prepare-corrected-checkout-v2.rb commit-corrections-v2.rb launch-measurement-stage-v3.rb
      export-completed-batch-v3.rb adapt-reconciled-followup-20261101.rb reconciled-followup-adaptation-20261101.json])
    selected.call(evaluation, "completion", %w[prepare-corrected-checkout-v3.rb commit-corrections-v3.rb
      launch-measurement-stage-v4.rb export-completed-batch-v4.rb adapt-final-replica-followup-20261101.rb
      final-replica-followup-adaptation-20261101.json timing-fix-adjudication-reuse-frozen.rb])
    if config.fetch('decision_overlays', []).any?
      reconciliation = JSON.parse(File.read(File.join(evaluation, config.fetch("replica_selection"))))
      selected.call(reconciliation.fetch("proposal_root"), "timing-corrections/proposals", %w[reused-proposals.json])
      parent_proposals = reconciliation.fetch("prior_reconciled_proposal_root")
      parent_review = File.join(home, "llm_timing_fixes", config.fetch("audit_id") + "-review")
      parent_adjudication = parent_review + "-sol61"
      selected.call(parent_proposals, "timing-corrections/selection-history/proposals", %w[manifest.yaml summary-full.jsonl reused-proposals.json])
      selected.call(File.join(parent_proposals, "materialized"), "timing-corrections/selection-history/compile-superset", %w[summary-full.yaml])
      selected.call(parent_review, "timing-corrections/selection-history/postfix-review", %w[manifest.yaml summary-full.jsonl reused-reviews.json])
      selected.call(parent_adjudication, "timing-corrections/selection-history/adjudication", %w[manifest.yaml environment-evidence.yaml summary-full.jsonl])
      selected.call(reconciliation.fetch("adjudication_root"), "timing-corrections/adjudication", %w[reused-reviews.json])
    end
    if selection
      selected.call(evaluation, 'completion', %w[audit-export-binding.json citation-syntax-amendment.json
        qt-optional-verification-fix.json retry-citation-syntax.rb finish-timing-verification.rb
        correction-template-reuse.json benchmark-template-reuse.json correction-driver.rb
        timing-review-driver.rb timing-handoff-policy.json export-scoped-replacements.rb])
    end
    final_review = LocalEvalArtifact.load_yaml(File.join(batch, "timing-corrections/adjudication/manifest.yaml")).fetch("review_root")
    raise "Unexpected correction review root" unless File.realpath(final_review).start_with?(File.join(home, "llm_timing_fixes", config.fetch("audit_id")) + "-review")
    selected.call(final_review,
      "timing-corrections/postfix-review", %w[reused-reviews.json])
    summary = JSON.parse(File.read(File.join(batch, "summary.json")))
    summary["benchmarking_performed"] = true
    summary.fetch("timing_corrections")["benchmarking_performed"] = true
    summary["generation"] = {
      "harness" => "opencode", "records" => expected_count,
      "exact_counters_verified" => observations.count { |row| row.fetch("usage_complete") },
      "native_requests" => context.fetch("requests"), "provider_retries" => observations.sum { |row| row.fetch("retry_count") },
      "excluded_retry_seconds" => observations.sum { |row| row.fetch("retry_backoff_seconds") }.round(6),
      "ordinary_cleanup_records" => cleanup.size, "api_time_available" => false,
      "common_configuration" => "generation/common-configuration.json", "pricing_reference" => "generation/pricing/pricing-reference.json"
    }
    incomplete = observations.reject { |row| row.fetch("usage_complete") }
    unless incomplete.empty?
      summary.fetch("generation").merge!("incomplete_usage_records" => incomplete.size,
        "incomplete_usage_ids" => incomplete.map { |row| row.fetch("id") }.sort,
        "partial_counter_policy" => "Exact completed-request counters are lower bounds only; full-task token and cost fields remain unavailable. Scientific validation and benchmark outcomes are independent.")
    end
    json.call("summary.json", summary)
    puts "Retained #{expected_count} OpenCode observations (#{expected_count - incomplete.size} complete usage, #{incomplete.size} partial), deduplicated configuration, cleanup and pricing evidence."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} audit|complete HOME [BATCH]" unless (2..3).cover?(ARGV.size)
  OpenCodeSupplement.run(root: File.expand_path("..", __dir__), home: File.expand_path(ARGV[1]), phase: ARGV.first,
    batch_id: ARGV.fetch(2, OpenCodeSupplement::DEFAULT_BATCH))
end
