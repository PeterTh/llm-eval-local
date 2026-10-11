# frozen_string_literal: true
require_relative "artifact_common"

# Checks retained batch evidence without needing the native workspace or Git sources.
module BatchVerification
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
    end
  end

  def verify_batch_audit_selection!(campaign, original, corrections, summary)
    relative = summary['timing_audit_selection']
    return unless relative
    base = "batches/#{campaign.fetch('id')}"
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
    base = "batches/#{campaign.fetch('id')}"
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
    end
  end
end
