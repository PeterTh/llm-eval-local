# frozen_string_literal: true
require_relative "artifact_common"

# Checks retained batch evidence without needing the native workspace or Git sources.
module BatchVerification
  def evidence_base(campaign)
    base = campaign.fetch('evidence_root', "batches/#{campaign.fetch('id')}")
    path(base) # Apply the release-relative path safety check.
    base
  end

  def verify_opencode_termination!(campaign, observation, row)
    id = observation.fetch('id')
    raise "unsafe termination identity #{id}" unless id.match?(/\A[a-zA-Z0-9_.-]+\z/) && campaign.fetch('id').match?(/\A\d{8}-\d{6}\z/)
    digest = observation.fetch('termination_record_sha256')
    file = path("#{evidence_base(campaign)}/generation/terminations/#{id}.json")
    raise "termination receipt changed #{id}" unless digest.match?(/\A[0-9a-f]{64}\z/) && sha256(file) == digest &&
      observation.fetch('sha256').fetch('generation-termination.txt') == digest
    receipt = JSON.parse(File.read(file))
    raise "termination receipt identity differs #{id}" unless receipt.fetch('schema_version') == 1 &&
      receipt.fetch('run_id') == id && receipt.fetch('session_id') == observation.fetch('session_id') &&
      receipt.fetch('reason') == 'model_caused_termination' && receipt.fetch('approved_by') == 'user' &&
      receipt.fetch('decision') == 'retain_original_without_restart' && receipt.fetch('usage_complete') == false &&
      receipt.fetch('native_process_receipt_available') == false && !observation.fetch('sha256').key?('opencode-process.txt')
    names = %w[output.txt timing.txt instruction.txt process-status.txt opencode-config.txt opencode-session.txt opencode-events.txt]
    raise "termination metadata differs #{id}" unless receipt.fetch('metadata_sha256') == observation.fetch('sha256').slice(*names)
    %w[incident_sha256 native_export_sha256].each do |key|
      raise "termination evidence missing #{id}" unless receipt.fetch(key).match?(/\A[0-9a-f]{64}\z/)
    end
    raise "partial usage differs #{id}" unless row.fetch('token_usage_complete') == 'false' &&
      row.fetch('generation_outcome') == 'generation_model_terminated' &&
      row.fetch('generation_failure_reason') == 'model_caused_termination' &&
      observation.fetch('generation_failure_reason') == 'model_caused_termination' &&
      row.fetch('termination_record_sha256') == digest &&
      JSON.parse(row.fetch('partial_token_counts')) == observation.fetch('token_counts')
  end

  def verify_generation_recovery!(campaign, observation, row)
    id = observation.fetch('id')
    recovered = observation.fetch('generation_time_recovered', false)
    flag = row['generation_time_recovered'].to_s
    raise "invalid generation recovery flag #{id}" unless [true, false].include?(recovered) &&
      ['', 'false', 'true'].include?(flag) && (flag == 'true') == recovered
    unless recovered
      raise "unflagged generation recovery metadata #{id}" if
        %w[generation_time_source generation_recovery_sha256 wrapper_exit_status_available].any? { |key| !row[key].to_s.empty? }
      return
    end
    raise "unsafe generation recovery identity #{id}" unless id.match?(/\A[a-zA-Z0-9_.-]+\z/) && campaign.fetch('id').match?(/\A\d{8}-\d{6}\z/)
    raise "unsupported generation recovery #{id}" unless observation.fetch('generation_time_source') == 'claude_result_duration_ms' &&
      observation.fetch('wrapper_exit_status_available') == false
    %w[generation_time_source wrapper_exit_status_available generation_recovery_sha256].each do |key|
      raise "generation recovery provenance differs #{id}/#{key}" unless row.fetch(key) == observation.fetch(key).to_s
    end
    digest = observation.fetch('generation_recovery_sha256')
    file = path("#{evidence_base(campaign)}/generation/recoveries/#{id}.json")
    raise "generation recovery receipt changed #{id}" unless digest.match?(/\A[0-9a-f]{64}\z/) && sha256(file) == digest &&
      observation.fetch('sha256').fetch('generation-recovery.txt') == digest
    receipt = JSON.parse(File.read(file))
    raise "generation recovery receipt identity differs #{id}" unless receipt.fetch('schema_version') == 1 &&
      receipt.fetch('run_id') == id && receipt.fetch('campaign_id') == campaign.fetch('id') &&
      receipt.fetch('approved_by') == 'user' && receipt.fetch('decision') == 'retain_completed_native_result' &&
      %w[model session_id version generation_time_source generation_time_recovered wrapper_exit_status_available].all? { |key| receipt.fetch(key) == observation.fetch(key) }
    raise "generation recovery duration differs #{id}" unless receipt.fetch('duration_ms').is_a?(Integer) &&
      receipt.fetch('duration_ms').positive? && receipt.fetch('duration_ms') / 1000.0 == observation.fetch('total_seconds') &&
      %w[wrapper_wall_time_seconds wrapper_start_time wrapper_end_time].all? { |key| receipt.fetch(key).nil? }
    %w[output.txt timing.txt instruction.txt process-status.txt].each do |name|
      raise "generation recovery metadata differs #{id}/#{name}" unless receipt.fetch('metadata_sha256').fetch(name) == observation.fetch('sha256').fetch(name)
    end
  end

  def verify_context_observations!(campaign, observations, records)
    by_id = observations.to_h { |row| [row.fetch('id'), row] }
    raise 'context usage scope differs' unless records.size == by_id.size && records.map { |row| row.fetch('id') }.sort == by_id.keys.sort
    records.each do |record|
      id = record.fetch('id')
      observation = by_id.fetch(id)
      raise "context usage identity differs #{id}" unless record.fetch('schema_version') == 1 &&
        record.fetch('source_batch') == campaign.fetch('id') && record.fetch('source_commit') == campaign.fetch('source_commit') &&
        record.fetch('session_id') == observation.fetch('session_id') && record.fetch('model') == observation.fetch('model') &&
        record.fetch('claude_code_version') == observation.fetch('version') &&
        record.fetch('transcript_sha256') == observation.fetch('sha256').fetch('output.txt') &&
        record.fetch('native_token_counts') == observation.fetch('token_counts')
      bands = record.fetch('bands')
      raise "context band scope differs #{id}" unless bands.keys.sort == %w[long short]
      keys = %w[input_tokens cache_read_input_tokens cache_creation_5m_tokens cache_creation_1h_tokens output_tokens inclusive_input_tokens requests max_request_input_tokens streamed_output_lower_bound]
      bands.each do |name, band|
        raise "invalid context count #{id}" unless keys.all? { |key| band.fetch(key).is_a?(Integer) && band.fetch(key) >= 0 }
        inclusive = band.values_at('input_tokens', 'cache_read_input_tokens', 'cache_creation_5m_tokens', 'cache_creation_1h_tokens').sum
        raise "context band input differs #{id}" unless inclusive == band.fetch('inclusive_input_tokens')
        maximum, requests = band.values_at('max_request_input_tokens', 'requests')
        raise "context request length differs #{id}" unless maximum <= inclusive && inclusive <= maximum * requests
        if requests.positive?
          raise "wrong context band #{id}" unless (maximum > record.fetch('request_input_threshold_tokens')) == (name == 'long')
        end
        raise "context output below lower bound #{id}" unless band.fetch('output_tokens') >= band.fetch('streamed_output_lower_bound')
        raise "context output without requests #{id}" if requests.zero? && band.fetch('output_tokens').positive?
      end
      expected = {
        'input_tokens' => bands.values.sum { |band| band.fetch('input_tokens') },
        'cache_read_input_tokens' => bands.values.sum { |band| band.fetch('cache_read_input_tokens') },
        'cache_creation_input_tokens' => bands.values.sum { |band| band.values_at('cache_creation_5m_tokens', 'cache_creation_1h_tokens').sum },
        'output_tokens' => bands.values.sum { |band| band.fetch('output_tokens') }
      }
      raise "context counters differ #{id}" unless expected == observation.fetch('token_counts') &&
        bands.values.sum { |band| band.fetch('requests') } == record.fetch('requests')
      mixed = bands.values.all? { |band| band.fetch('requests').positive? }
      label = mixed ? 'derived_from_reported_list_cost_and_native_output_total' : 'native_total_in_single_observed_band'
      raise "context output provenance differs #{id}" unless record.fetch('output_band_evidence') == label && record.fetch('per_request_output_available') == false
    end
  end

  def verify_generation_observations!(campaign, observations, rows, usage: nil)
    raise 'generation observation scope differs' unless observations.size == rows.size && observations.map { |r| r.fetch('id') }.sort == rows.keys.sort
    if usage
      raise 'generation usage scope differs' unless usage.keys.sort == rows.keys.sort
    end
    observations.each do |observation|
      id = observation.fetch('id')
      row = rows.fetch(id)
      if usage
        record = usage.fetch(id)
        raise "generation usage identity differs #{id}" unless record.fetch('batch') == campaign.fetch('id') &&
          record.fetch('session_id') == observation.fetch('session_id') &&
          record.fetch('session_cwd') == observation.fetch('session_cwd') &&
          record.fetch('cli_version') == observation.fetch('version') &&
          record.fetch('transcript_sha256') == observation.fetch('sha256').fetch('output.txt') &&
          record.fetch('legacy_reported_tokens') == observation.fetch('legacy_reported_tokens') &&
          row.fetch('model') == "#{observation.fetch('model')}-#{observation.fetch('reasoning_effort')}"
        counters = record.fetch('usage')
        expected = { 'input_tokens' => counters.fetch('input_tokens'), 'cached_tokens' => counters.fetch('cached_input_tokens'),
          'output_tokens' => counters.fetch('output_tokens'), 'total_tokens' => counters.fetch('total_tokens'),
          'reasoning_output_tokens' => counters['reasoning_output_tokens'], 'cache_write_input_tokens' => counters['cache_write_input_tokens'],
          'legacy_reported_tokens' => record.fetch('legacy_reported_tokens'), 'total_time' => observation.fetch('total_seconds'),
          'api_time' => observation['api_seconds'] }
        { 'token_usage_source' => record.fetch('source'), 'token_usage_session_id' => record.fetch('session_id') }.each do |key, value|
          raise "generation usage provenance differs #{id}/#{key}" unless row.fetch(key) == value
        end
      elsif campaign['generation_harness'] == 'opencode'
        provider, model = observation.fetch('model').split('/', 2)
        profile_model = { 'opencode-go/claude-haiku-5-5' => 'claude-haiku-5.5' }.fetch(observation.fetch('model'), model)
        complete = observation.fetch('usage_complete')
        raise "OpenCode generation identity differs #{id}" unless %w[openai opencode-go].include?(provider) &&
          model && !model.empty? && !model.include?('/') &&
          row.fetch('model') == "#{profile_model}-oc-#{observation.fetch('reasoning_effort')}" &&
          [true, false].include?(complete) && observation.fetch('usage_available') == true &&
          observation.fetch('outcome') == (complete ? 'completed' : 'generation_model_terminated') &&
          observation.fetch('usage_source') == 'opencode_native_step_finish'
        if complete
          raise "unexpected incomplete usage metadata #{id}" unless
            ['', 'true'].include?(row['token_usage_complete'].to_s) &&
            ['', 'completed'].include?(row['generation_outcome'].to_s) &&
            %w[partial_token_counts generation_failure_reason termination_record_sha256].all? { |key| row[key].to_s.empty? } &&
            %w[generation_failure_reason termination_record_sha256].all? { |key| observation[key].nil? }
        else
          verify_opencode_termination!(campaign, observation, row)
        end
        counters = observation.fetch('token_counts')
        names = %w[input_tokens cached_input_tokens cache_write_input_tokens output_tokens reasoning_output_tokens total_tokens]
        raise "OpenCode counters invalid #{id}" unless names.all? { |key| counters.fetch(key).is_a?(Integer) && counters.fetch(key) >= 0 } &&
          counters.fetch('input_tokens') >= counters.values_at('cached_input_tokens', 'cache_write_input_tokens').sum &&
          counters.fetch('output_tokens') >= counters.fetch('reasoning_output_tokens') &&
          counters.fetch('total_tokens') == counters.values_at('input_tokens', 'output_tokens').sum &&
          counters.fetch('total_tokens').positive? && counters.fetch('total_tokens') == observation.fetch('total_tokens')
        raw = observation.fetch('raw_total_seconds')
        retry_seconds = observation.fetch('retry_backoff_seconds')
        adjusted = observation.fetch('total_seconds')
        raise "OpenCode elapsed accounting differs #{id}" unless [raw, retry_seconds, adjusted].all? { |value| value.is_a?(Numeric) && value.finite? && value >= 0 } &&
          adjusted.positive? && (raw - retry_seconds - adjusted).abs < 0.000001 &&
          observation.fetch('retry_count').is_a?(Integer) && observation.fetch('retry_count') >= 0
        names = %w[output.txt timing.txt instruction.txt process-status.txt opencode-config.txt opencode-session.txt opencode-events.txt]
        names << (complete ? 'opencode-process.txt' : 'generation-termination.txt')
        names.each do |name|
          raise "OpenCode native metadata digest invalid #{id}/#{name}" unless observation.fetch('sha256').fetch(name).match?(/\A[0-9a-f]{64}\z/)
        end
        full_counts = complete ? counters : Hash.new(nil)
        expected = { 'input_tokens' => full_counts['input_tokens'], 'cached_tokens' => full_counts['cached_input_tokens'],
          'output_tokens' => full_counts['output_tokens'], 'total_tokens' => full_counts['total_tokens'],
          'reasoning_output_tokens' => full_counts['reasoning_output_tokens'], 'cache_write_input_tokens' => full_counts['cache_write_input_tokens'],
          'legacy_reported_tokens' => nil, 'raw_total_time' => raw, 'total_time' => adjusted,
          'agent_retry_backoff_seconds' => retry_seconds, 'agent_retry_count' => observation.fetch('retry_count'), 'api_time' => nil }
        { 'token_usage_source' => observation.fetch('usage_source'), 'token_usage_session_id' => observation.fetch('session_id') }.each do |key, value|
          raise "OpenCode usage provenance differs #{id}/#{key}" unless row.fetch(key) == value
        end
      else
        expected = { 'input_tokens' => observation.fetch('inclusive_input_tokens'),
          'cached_tokens' => observation.dig('token_counts', 'cache_read_input_tokens'),
          'output_tokens' => observation.dig('token_counts', 'output_tokens'), 'total_tokens' => observation.fetch('total_tokens'),
          'api_time' => observation.fetch('api_seconds'), 'total_time' => observation.fetch('total_seconds') }
      end
      expected.each do |key, value|
        actual = row.fetch(key)
        matches = value.nil? ? actual.to_s.empty? : Float(actual) == value
        raise "generation counter differs #{id}/#{key}" unless matches
      end
      verify_generation_recovery!(campaign, observation, row)
    end
  end

  def verify_opencode_context!(campaign, observations, context, context_records: nil)
    if context['pricing_context_policy'] == 'request_input_above_100000'
      return verify_opencode_context_bands!(campaign, observations, context, context_records)
    end
    raise 'Unexpected separate context records' unless context_records.nil?
    by_id = observations.to_h { |row| [row.fetch('id'), row] }
    records = context.fetch('records')
    flat = context.fetch('schema_version') == 2
    raise 'OpenCode flat-context pricing policy differs' if flat && !(context.fetch('pricing_context_policy') == 'flat_context' &&
      context.fetch('input_limit_tokens') == 1_000_000 && observations.all? { |row| row.fetch('model') == 'opencode-go/deepseek-v4.1-flash' })
    raise 'OpenCode context identity differs' unless [1, 2].include?(context.fetch('schema_version')) &&
      context.fetch('source_batch') == campaign.fetch('id') && context.fetch('source_commit') == campaign.fetch('source_commit') &&
      context.fetch('programs') == by_id.size && records.size == by_id.size && records.map { |row| row.fetch('id') }.sort == by_id.keys.sort
    records.each do |record|
      observation = by_id.fetch(record.fetch('id'))
      raise 'OpenCode context provenance differs' unless record.fetch('session_id') == observation.fetch('session_id') &&
        record.fetch('native_session_sha256') == observation.fetch('sha256').fetch('opencode-session.txt') &&
        record.fetch('token_counts') == observation.fetch('token_counts')
      requests, maximum = record.values_at('request_count', 'maximum_request_input_tokens')
      input = observation.fetch('token_counts').fetch('input_tokens')
      above = record.fetch('requests_above_272000_tokens')
      raise 'OpenCode context length differs' unless requests.is_a?(Integer) && requests.positive? && maximum.is_a?(Integer) &&
        maximum.positive? && maximum <= input && input <= maximum * requests && maximum <= (flat ? context.fetch('input_limit_tokens') : 272000) &&
        above.is_a?(Integer) && above.between?(0, requests) && (above.positive? == (maximum > 272000)) &&
        record.fetch('cache_write_input_tokens') == 0 &&
        observation.fetch('token_counts').fetch('cache_write_input_tokens') == 0
      raise 'OpenCode context completeness differs' if flat && record.fetch('usage_complete') != observation.fetch('usage_complete')
    end
    raise 'OpenCode context summary differs' unless context.fetch('requests') == records.sum { |row| row.fetch('request_count') } &&
      context.fetch('maximum_request_input_tokens') == records.map { |row| row.fetch('maximum_request_input_tokens') }.max &&
      context.fetch('requests_above_272000_tokens') == records.sum { |row| row.fetch('requests_above_272000_tokens') } && context.fetch('cache_write_input_tokens') == 0
    if flat
      raise 'OpenCode incomplete context totals differ' unless context.fetch('complete_programs') == observations.count { |row| row.fetch('usage_complete') } &&
        context.fetch('incomplete_programs') == observations.count { |row| !row.fetch('usage_complete') }
    end
  end

  def verify_opencode_context_bands!(campaign, observations, context, records)
    by_id = observations.to_h { |row| [row.fetch('id'), row] }
    raise 'OpenCode tiered-context scope differs' unless context.fetch('schema_version') == 2 && records.is_a?(Array) &&
      records.size == observations.size && by_id.size == observations.size &&
      records.map { |row| row.fetch('id') }.sort == by_id.keys.sort &&
      context.fetch('source_batch') == campaign.fetch('id') && context.fetch('source_commit') == campaign.fetch('source_commit') &&
      context.fetch('programs') == records.size && context.fetch('complete_programs') == records.size &&
      context.fetch('incomplete_programs') == 0 && context.fetch('usage_complete') == true
    records.each do |record|
      observation = by_id.fetch(record.fetch('id'))
      raise 'OpenCode tiered-context provenance differs' unless record.fetch('schema_version') == 2 &&
        record.fetch('batch') == campaign.fetch('id') && record.fetch('source_commit') == campaign.fetch('source_commit') &&
        record.fetch('profile') == 'claude-haiku-5.5-oc-medium' && observation.fetch('model') == 'opencode-go/claude-haiku-5-5' &&
        observation.fetch('reasoning_effort') == 'medium' &&
        record.fetch('session_id') == observation.fetch('session_id') &&
        record.fetch('native_session_sha256') == observation.fetch('sha256').fetch('opencode-session.txt') &&
        record.fetch('token_counts') == observation.fetch('token_counts') &&
        record.fetch('usage_complete') == true && observation.fetch('usage_complete') == true &&
        record.fetch('per_request_output_available') == true && record.fetch('output_band_evidence') == 'native_step_finish_per_request' &&
        record.fetch('request_input_threshold_tokens') == 100000
      bands = record.fetch('bands')
      raise 'OpenCode context bands differ' unless bands.keys.sort == %w[long short]
      bands.each do |name, band|
        fields = %w[requests input_tokens cache_read_input_tokens cache_write_input_tokens inclusive_input_tokens
          output_tokens reasoning_output_tokens max_request_input_tokens]
        raise 'Invalid OpenCode context counter' unless fields.all? { |key| band.fetch(key).is_a?(Integer) && band.fetch(key) >= 0 }
        requests, maximum, input, output = band.values_at('requests', 'max_request_input_tokens', 'inclusive_input_tokens', 'output_tokens')
        raise 'OpenCode context band totals differ' unless
          input == band.values_at('input_tokens', 'cache_read_input_tokens', 'cache_write_input_tokens').sum &&
          output >= band.fetch('reasoning_output_tokens')
        if requests.zero?
          raise 'OpenCode unused context band has tokens' unless input + output + maximum == 0
        else
          raise 'OpenCode context band lengths differ' unless maximum <= input && input <= maximum * requests &&
            maximum <= 1_000_000 && (maximum > 100000) == (name == 'long') &&
            (name != 'long' || input >= 100001 * requests)
        end
      end
      expected = { 'input_tokens' => 'inclusive_input_tokens', 'cached_input_tokens' => 'cache_read_input_tokens',
        'cache_write_input_tokens' => 'cache_write_input_tokens', 'output_tokens' => 'output_tokens',
        'reasoning_output_tokens' => 'reasoning_output_tokens' }.transform_values { |key| bands.values.sum { |band| band.fetch(key) } }
      expected['total_tokens'] = expected.values_at('input_tokens', 'output_tokens').sum
      raise 'OpenCode context counters differ' unless expected == observation.fetch('token_counts') &&
        record.fetch('requests') == bands.values.sum { |band| band.fetch('requests') } && record.fetch('requests').positive?
      raise 'Invalid OpenCode context cost' unless record.fetch('comparison_cost_nanodollars').is_a?(Integer) && record.fetch('comparison_cost_nanodollars') >= 0
    end
    raise 'OpenCode tiered-context summary differs' unless
      context.fetch('requests') == records.sum { |row| row.fetch('requests') } &&
      context.fetch('maximum_request_input_tokens') == records.flat_map { |row| row.fetch('bands').values.map { |band| band.fetch('max_request_input_tokens') } }.max &&
      context.fetch('requests_above_100000_tokens') == records.sum { |row| row.dig('bands', 'long', 'requests') } &&
      context.fetch('observations_with_long_requests') == records.count { |row| row.dig('bands', 'long', 'requests').positive? } &&
      context.fetch('comparison_cost_nanodollars') == records.sum { |row| row.fetch('comparison_cost_nanodollars') }
  end

  def verify_batch_audit_selection!(campaign, original, corrections, summary)
    relative = summary['timing_audit_selection']
    return unless relative
    base = evidence_base(campaign)
    selection = JSON.parse(File.read(path("#{base}/#{relative}")))
    raise 'resolved audit source differs' unless selection.fetch('schema_version') == 1 && selection.fetch('source_commit') == campaign.fetch('source_commit')
    resolved = {}
    inputs = selection.fetch('ordered_decisions')
    raise 'resolved audit input scope differs' if inputs.empty? || inputs.map { |r| r.fetch('path') }.uniq.size != inputs.size
    inputs.each do |input|
      file = path("#{base}/#{input.fetch('path')}")
      raise 'resolved audit input changed' unless sha256(file) == input.fetch('sha256')
      records = LocalEvalArtifact.read_jsonl(file)
      raise 'duplicate resolved audit ID' unless records.map { |r| r.fetch('program_id') }.uniq.size == records.size
      records.each do |record|
        id = record.fetch('program_id')
        if resolved[id]
          %w[benchmark model par_type run source_tree_oid source_digest].each do |key|
            raise "resolved audit source differs #{id}" unless record.fetch(key) == resolved.fetch(id).fetch(key)
          end
        end
        resolved[id] = record
      end
    end
    expected = original.values.select do |record|
      info = record.fetch('metadata')
      LocalEvalArtifact::VALIDATION_STAGES.all? { |stage| info.fetch('stages').fetch(stage) == true } &&
        (%w[mpi hybrid].include?(info.fetch('par_type')) || info.fetch('benchmark') == 'qtclustering')
    end.map { |record| record.fetch('id') }.sort
    raise 'resolved audit coverage differs' unless resolved.keys.sort == expected && resolved.size == selection.fetch('record_count')
    counts = resolved.values.group_by { |record| record.fetch('final_verdict') }.transform_values(&:size)
    raise 'resolved audit verdict counts differ' unless counts == selection.fetch('verdict_counts') && counts == summary.fetch('timing_audit_final_verdicts')
    resolved.each_value do |record|
      verdict = record.fetch('final_verdict')
      raise 'unresolved audit decision' unless %w[valid invalid].include?(verdict) && record.fetch('final_confidence') == 'high' &&
        record.fetch('timing_review_required') == false && record.fetch('timing_fix_required') == (verdict == 'invalid')
    end
    ids = resolved.values.select { |r| r.fetch('timing_fix_required') }.map { |r| r.fetch('program_id') }.sort
    raise 'resolved audit correction scope differs' unless ids == corrections.keys.sort && ids == selection.fetch('correction_ids')
    corrections.each do |id, correction|
      raise "resolved audit correction source differs #{id}" unless correction.fetch('original_source').fetch('digest') == resolved.fetch(id).fetch('source_digest')
    end
    correction_summary = summary.fetch('timing_corrections')
    raise 'resolved audit correction binding differs' unless correction_summary.fetch('audit_selection') == relative &&
      correction_summary.fetch('audit_selection_sha256') == sha256(path("#{base}/#{relative}"))
  end

  def verify_corrected_scientific_validation!(id, original, corrected)
    stages = corrected.fetch("metadata").fetch("stages")
    raise "corrected scientific validation failed #{id}" unless LocalEvalArtifact::VALIDATION_STAGES.all? { |stage| stages.fetch(stage) == true }
    [original, corrected].each do |record|
      raise "missing corrected validation output #{id}" unless record.fetch("logs").fetch("validation_out_stdout.log").match?(/=== RESULTS ===.*?=== END RESULTS ===/m)
    end
    # Native scientific validation is authoritative. Cross-run byte equality,
    # including result Hash fields ignored by that validator, is not a new gate.
  end

  def verify_batch(campaign, original, corrected, records)
    base = evidence_base(campaign)
    read_json = ->(relative) { JSON.parse(File.read(path("#{base}/#{relative}"))) }
    read_yaml = ->(relative) { LocalEvalArtifact.load_yaml(path("#{base}/#{relative}")) }
    summary = read_json.call("summary.json")
    benchmark_summary = read_json.call("benchmark/summary.json")
    raise "stale batch summary" unless summary.fetch("benchmark") == benchmark_summary
    counts = { "records" => records.size, "successful" => records.values.count { |r| r.fetch("success") },
               "failed" => records.values.count { |r| !r.fetch("success") },
               "timing_fixed" => records.values.count { |r| r.fetch("timing_fixed") },
               "timing_fixed_successful" => records.values.count { |r| r.fetch("timing_fixed") && r.fetch("success") } }
    raise "batch benchmark counts differ" unless counts.all? { |k, v| benchmark_summary.fetch(k) == v }
    raise "batch validation count differs" unless summary.fetch("validation_records") == original.size
    raise "batch validation pass count differs" unless summary.fetch("validation_passed") == records.size
    raise "batch correction count differs" unless summary.fetch("timing_corrections").fetch("benchmark_successful") == counts.fetch("timing_fixed_successful")
    manifest_digest = sha256(path(campaign.fetch("manifest")))
    corrected_manifest_digest = sha256(path("#{base}/timing-corrections/revalidation/provenance/evaluation_manifest.yaml"))
    [[original, campaign.fetch("source_commit"), manifest_digest],
     [corrected, campaign.fetch("corrected_source_commit"), corrected_manifest_digest]].each do |selection, commit, digest|
      selection.each do |id, validation|
        metadata = validation.fetch("metadata")
        raise "batch validation identity differs #{id}" unless metadata.fetch("id") == id && self.class.id(metadata.transform_values(&:to_s)) == id
        raise "batch validation source differs #{id}" unless validation.fetch("source_commit") == commit && validation.fetch("source_batch") == campaign.fetch("id")
        raise "batch validation manifest differs #{id}" unless metadata.fetch("manifest_sha256") == digest
        validation.fetch("logs").each do |name, content|
          raise "batch validation log digest differs #{id}/#{name}" unless Digest::SHA256.hexdigest(content) == validation.fetch("log_sha256").fetch(name)
        end
      end
    end
    corrections = LocalEvalArtifact.read_jsonl(path("#{base}/timing-corrections/final/corrections.jsonl"))
    by_id = corrections.to_h { |r| [r.fetch("program_id"), r] }
    verify_batch_audit_selection!(campaign, original, by_id, summary)
    raise "batch correction scope differs" unless by_id.size == corrections.size && by_id.keys.sort == corrected.keys.sort && by_id.keys.sort == records.values.select { |r| r.fetch("timing_fixed") }.map { |r| r.fetch("id") }.sort
    amendment_digest = sha256(path("#{base}/benchmark/provenance/source_correction_amendment.yaml"))
    by_id.each do |id, correction|
      record = records.fetch(id).fetch("timing_correction")
      raise "batch correction amendment differs #{id}" unless record.fetch("source_correction_amendment_sha256") == amendment_digest
      %w[original_source corrected_source].each do |field|
        %w[commit digest].each { |key| raise "batch correction source differs #{id}" unless record.fetch(field).fetch(key) == correction.fetch(field).fetch(key) }
        expected_url = "https://github.com/PeterTh/llm-eval-generated/tree/#{correction.fetch(field).fetch('commit')}/#{campaign.fetch('id')}/#{id}"
        raise "batch correction URL differs #{id}" unless record.fetch(field).fetch("url") == expected_url
      end
      raise "batch correction not accepted #{id}" unless correction.fetch("timing_fixed") && corrected.fetch(id).fetch("metadata").fetch("stages").values.all? { |value| value == true }
      verify_corrected_scientific_validation!(id, original.fetch(id), corrected.fetch(id))
    end
    metadata = read_yaml.call("aggregate/aggregate_metadata.yaml")
    { "manifest_sha256" => "provenance/evaluation_manifest.yaml",
      "benchmark_config_sha256" => "benchmark/provenance/benchmark_config.yaml",
      "source_correction_amendment_sha256" => "benchmark/provenance/source_correction_amendment.yaml" }.each do |key, relative|
      raise "stale batch aggregate #{key}" unless metadata.fetch(key) == sha256(path("#{base}/#{relative}"))
    end
    receipt = read_json.call("aggregate/export.json")
    raise "batch aggregate CSV differs from native export" unless receipt.fetch("native_aggregate_csv_sha256") == sha256(path(campaign.fetch("aggregate_csv")))
    raise "batch aggregate metadata differs from native export" unless receipt.fetch("native_aggregate_metadata_sha256") == sha256(path("#{base}/aggregate/aggregate_metadata.yaml"))
    raise "batch aggregate incomplete" unless metadata.fetch("complete") && metadata.fetch("record_count") == original.size && receipt.fetch("records") == original.size
    amendment_path = path("#{base}/benchmark/provenance/pipeline_amendment.yaml")
    amendment_digest = File.file?(amendment_path) ? sha256(amendment_path) : nil
    raise "stale batch aggregate pipeline_amendment_sha256" unless metadata.fetch("pipeline_amendment_sha256") == amendment_digest
    pipeline = if amendment_digest
      read_yaml.call("benchmark/provenance/pipeline_amendment.yaml").fetch("amended_pipeline_source").fetch("files")
    else
      read_yaml.call("provenance/evaluation_manifest.yaml").fetch("pipeline_source").fetch("files")
    end
    layout = read_json.call("benchmark/method/pipeline-layout.json")
    raise "batch pipeline file set differs" unless layout.keys.sort == pipeline.keys.sort
    layout.each { |name, relative| raise "batch pipeline hash differs #{name}" unless sha256(path("#{base}/#{relative}")) == pipeline.fetch(name) }
    if campaign['generation_manifest']
      generation = read_json.call('generation/campaign.json')
      generation_layout = if campaign['generation_method_layout']
        JSON.parse(File.read(path(campaign.fetch('generation_method_layout'))))
      else
        generation.fetch('files').to_h { |name, _| [name, "#{base}/generation/method/#{name}"] }
      end
      raise 'generation method file set differs' unless generation_layout.keys.sort == generation.fetch('files').keys.sort
      generation.fetch('files').each do |name, digest|
        raise "generation method changed #{name}" unless sha256(path(generation_layout.fetch(name))) == digest
      end
      if generation['runtime_amendment']
        runtime = read_json.call('generation/runtime-method-layout.json')
        amendment = read_json.call('generation/output-limit-amendment/amendment.json')
        output_limit_revision = runtime.fetch('source_commit')
        if generation['filesystem_amendment']
          previous = read_json.call('generation/filesystem-amendment/before-campaign.json')
          previous_layout = read_json.call('generation/pre-isolation-method-layout.json')
          binding = read_json.call('generation/filesystem-amendment/binding.json')
          output_limit_revision = previous.fetch('runtime_source_commit')
          raise 'filesystem amendment identity differs' unless binding.fetch('ids') == campaign.fetch('ids') &&
            binding.fetch('ids') == generation.fetch('filesystem_amendment').fetch('affected_observations').sort &&
            binding.fetch('source_commit') == runtime.fetch('source_commit') &&
            binding.fetch('previous_source_commit') == output_limit_revision &&
            binding.fetch('policy') == generation.fetch('generation_filesystem_policy') &&
            binding.fetch('before_campaign_sha256') == sha256(path("#{base}/generation/filesystem-amendment/before-campaign.json")) &&
            previous_layout.fetch('source_commit') == output_limit_revision &&
            previous_layout.fetch('files').keys.sort == previous.fetch('files').keys.sort
          previous_layout.fetch('files').each do |name, relative|
            raise "pre-isolation method changed #{name}" unless sha256(path(relative)) == previous.fetch('files').fetch(name)
          end
        end
        raise 'generation runtime identity differs' unless runtime.fetch('source_commit') == generation.fetch('runtime_source_commit') &&
          amendment.fetch('source_commit') == output_limit_revision && amendment.fetch('replacement_batch') == campaign.fetch('id') &&
          runtime.fetch('files').keys.sort == generation.fetch('files').keys.sort &&
          amendment.fetch('affected_observations').sort == generation.fetch('runtime_amendment').fetch('affected_observations').sort
        runtime.fetch('files').each do |name, binding|
          raise "generation runtime source changed #{name}" unless binding.fetch('path').start_with?('method/', 'batches/') &&
            !binding.fetch('path').split('/').include?('..') && sha256(path(binding.fetch('path'))) == binding.fetch('sha256') &&
            binding.fetch('sha256') == generation.fetch('files').fetch(name) && binding.fetch('path') == generation_layout.fetch(name)
        end
        initial = read_json.call('generation/output-limit-amendment/campaign-0-before.json')
        original_layout = read_json.call('generation/original-method-layout.json')
        raise 'original generation method identity differs' unless initial.fetch('campaign_id') == campaign.fetch('id') &&
          initial.fetch('source_commit') == generation.fetch('source_commit') && original_layout.fetch('source_commit') == initial.fetch('source_commit') &&
          original_layout.fetch('files').keys.sort == initial.fetch('files').keys.sort
        original_layout.fetch('files').each do |name, relative|
          raise "original generation method changed #{name}" unless sha256(path(relative)) == initial.fetch('files').fetch(name)
        end
      end
      observations = LocalEvalArtifact.read_jsonl(path("#{base}/generation/observations.jsonl"))
      rows = CSV.read(path(campaign.fetch('aggregate_csv')), headers: true).to_h { |r| [self.class.id(r), r] }
      usage = nil
      if campaign['exact_codex_usage']
        usage_path = path(campaign.fetch('exact_codex_usage'))
        raise 'native aggregate Codex usage binding differs' unless metadata.fetch('codex_usage_sha256') == sha256(usage_path)
        recovery = read_json.call('generation/usage-recovery.json')
        usage = CodexUsage.load_records(usage_path)
        raise 'generation usage receipt differs' unless recovery.fetch('sha256') == sha256(usage_path) &&
          recovery.fetch('records') == usage.size && recovery.fetch('unavailable').empty?
      end
      verify_generation_observations!(campaign, observations, rows, usage: usage)
      if campaign['generation_harness'] == 'opencode'
        raise 'OpenCode generation harness differs' unless generation.fetch('harness') == 'opencode' && usage.nil?
        common_path = path("#{base}/generation/common-configuration.json")
        common = JSON.parse(File.read(common_path))
        observations.each do |observation|
          profile = rows.fetch(observation.fetch('id')).fetch('model')
          declared = generation.fetch('models').fetch(profile)
          raise 'OpenCode generation profile differs' unless observation.fetch('model') == declared.fetch('model') &&
            observation.fetch('reasoning_effort') == declared.fetch('reasoning_effort') &&
            observation.fetch('version') == generation.fetch('opencode_version') &&
            observation.fetch('common_configuration_sha256') == sha256(common_path) &&
            common.fetch('resolved_model').fetch('id') == observation.fetch('model').split('/', 2).last &&
            common.fetch('resolved_model').fetch('providerID') == observation.fetch('model').split('/', 2).first
          if generation['filesystem_amendment']
            isolation = observation.fetch('filesystem_isolation')
            raise 'generation filesystem isolation differs' unless isolation.fetch('policy') == generation.fetch('generation_filesystem_policy') &&
              isolation.fetch('implementation_sha256') == generation.fetch('files').fetch('lib/generation_filesystem.rb') &&
              isolation.fetch('bubblewrap_sha256').match?(/\A[0-9a-f]{64}\z/) &&
              isolation.fetch('workspace') == "#{generation.fetch('workspace')}/#{observation.fetch('id')}" &&
              isolation.fetch('preflight') == { 'passed' => true, 'operator_home_visible' => false, 'other_observations_visible' => false } &&
              isolation.fetch('network') == 'unchanged' && isolation.fetch('hardware_devices') == 'unchanged'
          end
        end
        context = read_json.call('generation/pricing/request-context-summary.json')
        context_records = nil
        if context['pricing_context_policy'] == 'request_input_above_100000'
          relative = "#{base}/generation/pricing/context-usage.jsonl"
          raise 'OpenCode request-context binding differs' unless campaign.fetch('opencode_context_usage') == relative &&
            sha256(path(relative)) == context.fetch('context_usage_sha256')
          context_records = LocalEvalArtifact.read_jsonl(path(relative))
        end
        verify_opencode_context!(campaign, observations, context, context_records: context_records)
      end
      if campaign['context_token_usage']
        context_path = path(campaign.fetch('context_token_usage'))
        context_records = LocalEvalArtifact.read_jsonl(context_path)
        recovery = read_json.call('generation/context-usage/recovery.json')
        raise 'context recovery binding differs' unless recovery.fetch('records') == context_records.size &&
          recovery.fetch('usage_sha256') == sha256(context_path) && recovery.fetch('source_commit') == campaign.fetch('source_commit')
        context_layout = read_json.call('generation/context-usage/method-layout.json')
        raise 'context method scope differs' unless context_layout.keys.sort == recovery.fetch('method_files').keys.sort
        recovery.fetch('method_files').each do |name, digest|
          raise "context method changed #{name}" unless sha256(path(context_layout.fetch(name))) == digest
        end
        verify_context_observations!(campaign, observations, context_records)
      end
    end
  end
end
