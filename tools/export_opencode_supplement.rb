#!/usr/bin/env ruby
# frozen_string_literal: true

# Compact OpenCode-specific evidence. Established exporters retain native
# validation, timing corrections and measurements; no generated programs run here.
require_relative "artifact_common"
require "open3"

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
    report = JSON.parse(File.read(File.join(evaluation, selection ? 'audit-export-binding.json' : 'audit-completion-review.json')))
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
        "schema_version" => 1, "source_commit" => original, "record_count" => decisions.size,
        "ordered_decisions" => inputs, "verdict_counts" => counts, "correction_ids" => correction_ids,
        "policy" => "Same-source all-backend QT boundary decisions overlay the general MPI/hybrid audit; all review evidence is retained."
      })
      write.call("timing-audit/conditional-decisions.jsonl", "")
      selected.call(evaluation, "completion", %w[audit-completion-review.json verify-audit-completion.rb review-policy.json
        prepare-review-policy.rb verify-primary-pilot.rb audit-pilot-driver.rb audit-full-driver-policy.rb
        audit-pilot-launch.json audit-full-launch.json timing-platform-context.txt
        audit-pilot-resume-1.json audit-pilot-resume-2.json resume-audit-pilot.rb resume-audit-pilot-2.rb])
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
    pricing = selection ? selection.fetch('pricing') : File.join(campaign, "pricing")
    context = JSON.parse(File.read(File.join(pricing, "request-context-summary.json")))
    context_records = nil
    if context['pricing_context_policy'] == 'request_input_above_100000'
      context_path = File.join(pricing, 'context-usage.jsonl')
      raise 'OpenCode request-context evidence changed' unless LocalEvalArtifact.sha256(context_path) == context.fetch('context_usage_sha256')
      context_records = LocalEvalArtifact.read_jsonl(context_path)
    end
    verifier.verify_opencode_context!({ "id" => batch_id, "source_commit" => original }, observations, context, context_records: context_records)
    selected.call(pricing, "generation/pricing", %w[pricing-reference.json request-context-summary.json context-usage.jsonl retain-pricing-context.rb retain-pricing-reference.rb
      pricing-refresh.json deepseek-refresh-current-pricing-20261024.rb current-context-review.json deepseek-bind-current-context-20261024.rb])
    selected.call(evaluation, "completion", %w[campaign.json validation-launch-gate.json validation-completion-review.json
      correction-pilot-gate.json correction-commit.json source-correction-push.json revalidation-completion-review.json
      revalidation-output-order-review.json record-revalidation-output-order.rb
      validation-failure-review.json record-validation-failure-review.rb aggregate-export-amendment.json
      apply-aggregate-export-amendment.rb
      benchmark-canary-gate.json benchmark-completion-review.json benchmark-progress.json
      verify-validation-completion.rb verify-correction-pilot.rb verify-revalidation-completion.rb verify-benchmark-records.rb
      commit-corrections.rb benchmark-driver.rb canary-driver.rb correction-pilot-driver.rb correction-full-driver.rb
      revalidation-driver.rb validation-launch.json correction-pilot-launch.json correction-full-launch.json
      correction-pilot-recovery-launch.json correction-pilot-recovery-progress.json
      resume-correction-pilot-driver.rb launch-correction-pilot-recovery.rb
      paced-correction-driver.rb launch-paced-corrections.rb
      correction-pilot-paced-launch.json correction-pilot-paced-activation.json correction-pilot-paced-progress.json
      correction-full-paced-launch.json correction-full-paced-activation.json correction-full-paced-progress.json
      correction-pilot-paced-startup-recovery.json retry-paced-startup.rb launch-paced-corrections-current.rb
      revalidation-launch.json canary-launch.json benchmark-launch.json benchmark-driver-template-reuse.json
      prepare-benchmark-drivers.rb prepare-corrected-checkout.rb corrected-checkout.json correction-driver-template-reuse.json correction-template-context.json
      benchmark-export-template-reuse.json prepare-release-export.rb export-completed-batch.rb
      correction-revision-1.json correction-revision-feedback.json correction-revision-launch.json
      correction-revision-driver.rb reuse-unchanged-correction-reviews.rb
      correction-followup-rebinding.json prepare-revised-correction-followup.rb])
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
