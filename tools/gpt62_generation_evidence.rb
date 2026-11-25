# frozen_string_literal: true

require 'bigdecimal'
require_relative 'artifact_common'
require_relative 'codex_usage_records'

# Compact native evidence only. No sessions are reread and no programs or models
# are invoked. The standard native exporters own validation and measurements.
module Gpt62GenerationEvidence
  BATCH = '20261123-155235'
  ORIGINAL = '7a0a8b8e28af48d4ee2525c13ced317726536b25'
  PROFILES = %w[gpt-6.2-astra-medium gpt-6.2-sol-medium].freeze
  module_function

  def safe_relative!(name)
    raise 'Unsafe evidence path' if name.empty? || Pathname.new(name).absolute? ||
      name.split('/').any? { |part| %w[. ..].include?(part) }
    name
  end

  def sha(path)
    raise "Non-regular evidence: #{path}" unless File.file?(path) && !File.symlink?(path)
    Digest::SHA256.file(path).hexdigest
  end

  def verify_observations!(observations, rows, completion, usage)
    raise 'Wrong original completion' unless completion.fetch('source_commit') == ORIGINAL &&
      completion.fetch('observations') == 440 && completion.fetch('normal_generation_exits') == 440 &&
      completion.fetch('by_model') == { 'gpt-6.2-astra' => 220, 'gpt-6.2-sol' => 220 }
    ids = observations.map { |row| row.fetch('id') }
    raise 'Generation scope differs' unless ids.size == 440 && ids.uniq.size == 440 &&
      ids.sort == rows.keys.sort && ids.sort == usage.keys.sort
    raise 'Accepted sessions not unique' unless observations.map { |row| row.fetch('session_id') }.uniq.size == 440
    counts = Hash.new(0)
    observations.each do |observation|
      id = observation.fetch('id')
      profile = "#{observation.fetch('model')}-#{observation.fetch('reasoning_effort')}"
      record = usage.fetch(id)
      row = rows.fetch(id)
      raise "Wrong accepted observation: #{id}" unless PROFILES.include?(profile) &&
        observation.fetch('outcome') == 'completed' && observation.fetch('version') == '0.171.0' &&
        record.fetch('batch') == BATCH && record.fetch('session_id') == observation.fetch('session_id') &&
        record.fetch('session_cwd') == observation.fetch('session_cwd') &&
        record.fetch('cli_version') == observation.fetch('version') &&
        record.fetch('transcript_sha256') == observation.fetch('sha256').fetch('output.txt') &&
        record.fetch('legacy_reported_tokens') == observation.fetch('legacy_reported_tokens') &&
        row.fetch('model') == profile
      isolation = observation.fetch('filesystem_isolation')
      raise "Isolation differs: #{id}" unless isolation.fetch('policy') == 'observation-mount-allowlist-v1' &&
        isolation.dig('preflight', 'passed') && isolation.dig('preflight', 'operator_home_visible') == false &&
        isolation.dig('preflight', 'other_observations_visible') == false
      catalog = observation.fetch('model_catalog')
      raise "Catalog identity differs: #{id}" unless catalog.fetch('model') == observation.fetch('model') &&
        catalog.fetch('effort') == 'medium' && catalog.fetch('definitions_modified') == false
      counters = record.fetch('usage')
      expected = {
        'input_tokens' => counters.fetch('input_tokens'), 'cached_tokens' => counters.fetch('cached_input_tokens'),
        'output_tokens' => counters.fetch('output_tokens'), 'total_tokens' => counters.fetch('total_tokens'),
        'reasoning_output_tokens' => counters.fetch('reasoning_output_tokens'),
        'cache_write_input_tokens' => counters.fetch('cache_write_input_tokens'),
        'legacy_reported_tokens' => record.fetch('legacy_reported_tokens'),
        'total_time' => observation.fetch('total_seconds')
      }
      expected.each do |key, value|
        raise "Aggregate differs: #{id}/#{key}" unless Float(row.fetch(key)) == value
      end
      raise "Usage provenance differs: #{id}" unless row.fetch('token_usage_source') == record.fetch('source') &&
        row.fetch('token_usage_session_id') == record.fetch('session_id')
      counts[profile] += 1
    end
    raise 'Profile population differs' unless counts == PROFILES.to_h { |profile| [profile, 220] }
    raise 'Final token total differs' unless usage.values.sum { |row| row.fetch('usage').fetch('total_tokens') } ==
      completion.fetch('exact_usage').fetch('total_tokens')
  end

  def verify_requests!(requests, usage, observations, audit, reference)
    by_id = observations.to_h { |row| [row.fetch('id'), "#{row.fetch('model')}-#{row.fetch('reasoning_effort')}"] }
    raise 'Request scope differs' unless requests.size == usage.size &&
      requests.map { |row| row.fetch('run_id') }.sort == usage.keys.sort
    raise 'Wrong selected pricing' unless reference.fetch('status') == 'selected_by_user' &&
      reference.fetch('selected') == { 'provider' => 'OpenAI', 'service_tier' => 'default',
        'pricing_tier' => 'standard', 'background_discount' => false } &&
      reference.fetch('profiles').keys.sort == PROFILES.sort &&
      reference.fetch('context_threshold_input_tokens') == 272_000 &&
      audit.fetch('context_threshold_input_tokens') == 272_000
    costs = PROFILES.to_h { |profile| [profile, BigDecimal('0')] }
    counts = Hash.new(0)
    maxima = Hash.new(0)
    profile_totals = PROFILES.to_h { |profile| [profile, Hash.new(0)] }
    requests.each do |row|
      id = row.fetch('run_id')
      original = usage.fetch(id)
      profile = by_id.fetch(id)
      raise "Request provenance differs: #{id}" unless row.fetch('batch') == BATCH &&
        row.fetch('session_id') == original.fetch('session_id') &&
        row.fetch('session_sha256') == original.fetch('session_sha256') &&
        row.fetch('exact_final_record_sha256') == Digest::SHA256.hexdigest(JSON.generate(original)) &&
        row.fetch('total_usage') == original.fetch('usage')
      entries = row.fetch('requests')
      raise "Request count differs: #{id}" unless entries.size == row.fetch('request_count') && !entries.empty?
      identifiers = entries.map { |entry| entry.fetch('response_id_sha256') }
      raise "Duplicate request identity: #{id}" unless identifiers.uniq.size == identifiers.size &&
        identifiers.all? { |identifier| identifier.match?(/\A[0-9a-f]{64}\z/) }
      totals = Hash.new(0)
      maximum = 0
      entries.each do |entry|
        counters = entry.fetch('usage')
        CodexUsage.validate_usage!(counters)
        raise 'Request counters incomplete' unless counters.keys.sort == original.fetch('usage').keys.sort
        counters.each { |key, value| totals[key] += value; profile_totals.fetch(profile)[key] += value }
        input = counters.fetch('input_tokens')
        cached = counters.fetch('cached_input_tokens')
        raise 'Unexpected long-context request or cache write' unless input <= 272_000 &&
          counters.fetch('cache_write_input_tokens').zero?
        rates = reference.fetch('profiles').fetch(profile).fetch('short_rates_usd_per_million')
        costs[profile] += ((input - cached) * BigDecimal(rates.fetch('input').to_s) +
          cached * BigDecimal(rates.fetch('cached_input').to_s) +
          counters.fetch('output_tokens') * BigDecimal(rates.fetch('output').to_s)) / 1_000_000
        maximum = [maximum, input].max
      end
      raise "Request sum/max differs: #{id}" unless totals == original.fetch('usage') &&
        maximum == row.fetch('max_request_input_tokens')
      counts[profile] += entries.size
      maxima[profile] = [maxima[profile], maximum].max
    end
    PROFILES.each do |profile|
      expected = audit.fetch('profiles').fetch(profile)
      raise "Request audit differs: #{profile}" unless counts.fetch(profile) == expected.fetch('requests') &&
        maxima.fetch(profile) == expected.fetch('max_request_input_tokens') &&
        profile_totals.fetch(profile) == expected.fetch('total_usage') &&
        expected.dig('by_context_tier', 'long', 'requests').zero?
      summary = reference.fetch('profiles').fetch(profile).fetch('cost_summary')
      raise "Standard cost differs: #{profile}" unless costs.fetch(profile) == BigDecimal(summary.fetch('total_usd')) &&
        ((costs.fetch(profile) / 220) - BigDecimal(summary.fetch('mean_usd_per_observation'))).abs < BigDecimal('1e-30')
    end
    { 'requests' => counts.values.sum, 'requests_by_profile' => counts,
      'standard_cost_totals_usd' => costs.transform_values { |cost| cost.to_s('F') } }
  end

  def retain_policy_history!(evaluation:, audit:, copy:, jsonl:)
    path = File.join(evaluation, 'black-scholes-preprocessing-policy.json')
    policy = JSON.parse(File.read(path))
    raise 'Fixed-size setup policy unresolved' unless policy.fetch('status') == 'resolved' &&
      policy.fetch('standard_pipeline_may_continue') && policy.fetch('application_root') == audit + '-black-scholes-setup-policy'
    policy.fetch('evidence_sha256').each { |file, digest| raise "Policy evidence changed: #{file}" unless sha(file) == digest }
    { 'user_decision_path' => 'user_decision_sha256', 'application_review_path' => 'application_review_sha256' }.each do |file_key, digest_key|
      raise 'Policy resolution evidence changed' unless sha(policy.fetch(file_key)) == policy.fetch(digest_key)
    end
    %w[black-scholes-preprocessing-policy.json retain-boundary-policy-hold.rb
      audit-completion-before-cross-review.json audit-completion-before-root-binding.json
      reconcile-timing-overlap.rb finalize-timing-overlap.rb finalize-timing-overlap-before-root-binding.rb
      correction-root-binding-repair.json repair-correction-root-binding.rb correction-pilot-resume.json
      resume-correction-pilot.rb default-visible-set-selection.json default-visible-set-proposal.json
      record-release-choices.rb].each do |name|
      source = File.join(evaluation, name)
      copy.call(source, "completion/#{name}") if File.file?(source)
    end
    %w[user-decision.json initial-policy-hold.json policy-before-application.json policy-context.txt
      application-quality-review.json apply-black-scholes-setup-policy.rb verify-black-scholes-policy.rb].each do |name|
      source = File.join(evaluation, 'black-scholes-setup-policy', name)
      copy.call(source, "timing-audit/setup-policy-history/#{name}") if File.file?(source)
    end
    source = audit + '-black-scholes-boundary-sol61-v2'
    destination = 'timing-audit/pre-policy-spotcheck'
    %w[manifest.yaml inventory.jsonl excluded.jsonl trial-ids.txt prompt-template.txt result-schema.json
      runner-snapshot.rb preparer-snapshot.rb static-evidence-snapshot.rb platform-context.txt
      summary-full.jsonl summary-full.csv].each do |name|
      file = File.join(source, name)
      copy.call(file, "#{destination}/#{name}") if File.file?(file)
    end
    results = Dir[File.join(source, 'results/*.json')].sort.map { |file| JSON.parse(File.read(file)) }
    raise 'Pre-policy spotcheck scope differs' unless results.map { |row| row.fetch('program_id') }.sort == policy.fetch('ids').sort
    jsonl.call("#{destination}/results.jsonl", results)
    attempts = Dir[File.join(source, 'logs/*/attempt-*/metadata.yaml')].sort.map do |file|
      metadata = LocalEvalArtifact.load_yaml(file)
      events = LocalEvalArtifact.read_jsonl(File.join(File.dirname(file), 'events.jsonl'))
      raise 'Non-static pre-policy review' if events.any? { |event| event['item'] && !%w[agent_message reasoning error].include?(event.fetch('item')['type']) }
      errors = events.filter_map { |event| event['message'] if event['type'] == 'error' }.uniq
      metadata['exported_transport_errors'] = errors unless errors.empty?
      metadata
    end
    jsonl.call("#{destination}/attempts.jsonl", attempts)
    # Raw findings are historical, not operative decisions. The retained policy
    # receipt explains the sequential-reference citation distinction explicitly.
  end

  def retain(campaign:, root:, rows:, copy:, json:, jsonl:, write:)
    completion = JSON.parse(File.read(File.join(campaign, 'completion-audit.json')))
    observations = Dir[File.join(campaign, 'observations/*.json')].sort.map { |path| JSON.parse(File.read(path)) }
    usage_path = File.join(campaign, 'codex-usage.jsonl')
    usage = CodexUsageRecords.load_records(usage_path)
    receipt = JSON.parse(File.read(File.join(campaign, 'usage-recovery.json')))
    raise 'Usage recovery differs' unless receipt == completion.fetch('exact_usage') &&
      receipt.fetch('records') == 440 && receipt.fetch('unavailable').empty? &&
      receipt.fetch('interrupted_request_usage_uncertain').empty? && receipt.fetch('sha256') == sha(usage_path)
    verify_observations!(observations, rows, completion, usage)
    cleanup = Dir[File.join(campaign, 'cleanup/*.json')].sort.map { |path| JSON.parse(File.read(path)) }
    raise 'Cleanup scope differs' unless cleanup.map { |row| row.fetch('id') }.sort == rows.keys.sort &&
      cleanup.all? { |row| row.fetch('verified_empty') }

    pricing = File.join(campaign, 'pricing')
    audit_path = File.join(pricing, 'request-context-audit.json')
    request_path = File.join(pricing, 'codex-request-usage.jsonl')
    reference_path = File.join(pricing, 'pricing-reference.json')
    audit = JSON.parse(File.read(audit_path))
    reference = JSON.parse(File.read(reference_path))
    raise 'Request audit binding differs' unless audit.fetch('observations') == 440 &&
      audit.fetch('generation_complete_before_session_inspection') &&
      audit.fetch('no_measurements_active_during_inspection') && audit.fetch('final_usage_sha256') == sha(usage_path) &&
      audit.fetch('request_usage_sha256') == sha(request_path) && audit.fetch('request_usage_bytes') == File.size(request_path)
    reference.fetch('input_sha256').each { |path, digest| raise "Pricing input changed: #{path}" unless sha(path) == digest }
    reference.fetch('sources').each do |name, source|
      safe_relative!(name)
      raise "Frozen pricing source changed: #{name}" unless sha(File.join(pricing, name)) == source.fetch('sha256')
    end
    options = JSON.parse(File.read(File.join(pricing, 'pricing-options.json')))
    scenarios = JSON.parse(File.read(File.join(pricing, 'cost-scenarios.json')))
    PROFILES.each do |profile|
      selected = reference.fetch('profiles').fetch(profile)
      raise "Selected Standard rates differ: #{profile}" unless selected.fetch('short_rates_usd_per_million') ==
        options.fetch('standard_rates_usd_per_million').fetch(profile) && selected.fetch('cost_summary') ==
        scenarios.fetch('costs').fetch(profile).fetch('standard')
    end
    verified_requests = verify_requests!(LocalEvalArtifact.read_jsonl(request_path), usage, observations, audit, reference)

    destination = File.join(root, 'metadata/codex-usage', BATCH + '.jsonl')
    FileUtils.mkdir_p(File.dirname(destination))
    raise 'Existing exact usage differs' if File.exist?(destination) && sha(destination) != sha(usage_path)
    FileUtils.cp(usage_path, destination)
    jsonl.call('generation/observations.jsonl', observations)
    jsonl.call('generation/cleanup.jsonl', cleanup)
    selected = lambda do |directory, names, optional: false|
      names.each do |name|
        relative = safe_relative!([directory, name].reject(&:empty?).join('/'))
        source = File.join(campaign, relative)
        next if optional && !File.exist?(source)
        sha(source)
        copy.call(source, "generation/#{relative}")
      end
    end
    selected.call('', %w[campaign.json run-ids.txt preflight-ids.txt preflight-review.json completion.json
      completion-audit.json usage-recovery.json model-catalog.json model-catalog.json.receipt.json])
    selected.call('', %w[preflight-gate.json preflight-usage-recovery.json preflight-launch.json run-launch.json
      original-source-push.json source-retention-push.json], optional: true)
    selected.call('preparation', %w[regression-tests.json regression-tests.log model-access.json filesystem-preflight.json
      features.json install.json tooling-commit.json catalog.json prepare-catalog.rb prepare-campaign.rb
      controller.rb run.rb monitor.rb launch.rb])
    selected.call('pricing', %w[pricing-reference.json pricing-options.json cost-scenarios.json request-context-audit.json
      codex-request-usage.jsonl read-request-usage.rb test-request-usage.rb codex_usage.rb prepare-request-reader.rb
      audit-request-context.rb retain-pricing-sources.rb compute-cost-scenarios.rb preparation.json tests.log
      astra-model.md sol-model.md pricing.md background.md])

    manifest = JSON.parse(File.read(File.join(campaign, 'campaign.json')))
    raise 'Campaign identity differs' unless manifest.fetch('campaign_id') == BATCH && manifest.fetch('expected_runs') == 440 &&
      manifest.fetch('models').keys.sort == PROFILES.sort && manifest.fetch('harness') == 'codex' &&
      manifest.fetch('codex_version') == '0.171.0' && manifest.dig('delegation', 'native') == false
    reusable = {}
    LocalEvalArtifact.regular_files(root).each do |path|
      relative = LocalEvalArtifact.relative_path(root, path)
      next unless relative.start_with?('method/') || relative.match?(%r{\Abatches/[^/]+/(?:method|generation/(?:method|runtime-method)|timing-corrections/method|benchmark/method)/})
      reusable[sha(path)] ||= relative
    end
    layout = manifest.fetch('files').to_h do |name, digest|
      source = File.join(campaign, 'method', safe_relative!(name))
      raise "Generation method changed: #{name}" unless sha(source) == digest
      relative = reusable[digest]
      unless relative
        stored = "generation/method/#{name.gsub('/bin/', '/commands/')}"
        copy.call(source, stored)
        relative = "batches/#{BATCH}/#{stored}"
        reusable[digest] = relative
      end
      [name, relative]
    end
    json.call('generation/method-layout.json', layout)
    { 'records' => 440, 'exact_counters_verified' => 440, 'provider_capacity_retries' => 0,
      'pricing' => 'generation/pricing/pricing-reference.json',
      'request_context_evidence' => 'generation/pricing/request-context-audit.json' }.merge(verified_requests)
  end
end
