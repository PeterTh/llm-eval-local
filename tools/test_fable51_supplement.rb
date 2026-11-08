# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'export_fable51_supplement'

class Fable51SupplementTest < Minitest::Test
  E = Fable51GenerationEvidence

  def setup
    @observations = 220.times.map do |index|
      row = {
        'id' => "synthetic_r#{index + 1}", 'session_id' => "session-#{index}",
        'outcome' => 'completed', 'model' => 'claude-fable-5-1', 'version' => '2.1.287',
        'retry_count' => 0, 'retry_backoff_seconds' => 0.0,
        'token_counts' => { 'input_tokens' => 2, 'cache_creation_input_tokens' => 3,
          'cache_read_input_tokens' => 20, 'output_tokens' => 7 },
        'inclusive_input_tokens' => 25, 'total_tokens' => 32,
        'total_seconds' => 10.5, 'api_seconds' => 3.0
      }
      row['filesystem_isolation'] = {} if index < 125
      row
    end
    @rows = @observations.to_h do |row|
      [row.fetch('id'), { 'input_tokens' => '25', 'output_tokens' => '7', 'cached_tokens' => '20',
        'total_tokens' => '32', 'total_time' => '10.5', 'api_time' => '3.0' }]
    end
    @completion = {
      'source_commit' => E::ORIGINAL, 'observations' => 220, 'accepted_generation_invocations' => 220,
      'outcomes' => { 'completed' => 220 }, 'total_tokens' => 7040, 'generation_seconds' => 2310.0,
      'isolated_observations' => 125, 'pre_isolation_observations_preserved' => 95
    }
  end

  def test_identity_and_accepted_attempt_accounting
    assert_equal '20261011-092100', Fable51Supplement::BATCH
    assert_equal 'claude-fable-5.1-cc-medium', E::PROFILE
    assert_nil E.verify_observations!(@observations, @rows, @completion)
  end

  def test_rejects_duplicate_accepted_session
    @observations.last['session_id'] = @observations.first.fetch('session_id')
    assert_raises(RuntimeError) { E.verify_observations!(@observations, @rows, @completion) }
  end

  def test_rejects_incorrect_inclusive_input_accounting
    @observations.first['inclusive_input_tokens'] = 5
    assert_raises(RuntimeError) { E.verify_observations!(@observations, @rows, @completion) }
  end

  def test_rejects_extra_subtraction_from_accepted_attempt_time
    @rows.values.first['total_time'] = '5.5'
    assert_raises(RuntimeError) { E.verify_observations!(@observations, @rows, @completion) }
  end

  def test_rejects_changed_isolation_population
    @observations.last['filesystem_isolation'] = {}
    assert_raises(RuntimeError) { E.verify_observations!(@observations, @rows, @completion) }
  end

  def test_rejects_missing_observation_and_wrong_source_revision
    assert_raises(RuntimeError) { E.verify_observations!(@observations.drop(1), @rows, @completion) }
    @completion['source_commit'] = '0' * 40
    assert_raises(RuntimeError) { E.verify_observations!(@observations, @rows, @completion) }
  end

  def test_rejects_unsupported_phase_before_writing
    assert_raises(RuntimeError) { Fable51Supplement.run(root: '/nonexistent', home: '/nonexistent', phase: 'publish') }
  end

  def test_evidence_paths_cannot_escape_the_batch
    %w[/absolute ../parent child/../parent ./same].each do |path|
      assert_raises(RuntimeError) { E.safe_relative!(path) }
    end
    assert_equal 'child/evidence.json', E.safe_relative!('child/evidence.json')
  end

  def test_preserves_native_export_schema_failure_diagnostics
    metadata = { 'program_id' => 'example', 'attempt' => 1, 'events_sha256' => 'bound' }
    previous = metadata.merge('exported_response_validation_error' => 'Invalid citation range')
    assert_equal previous, Fable51Supplement.preserve_native_attempt_diagnostics(metadata, previous)
    assert_equal metadata, Fable51Supplement.preserve_native_attempt_diagnostics(metadata, nil)
    refute metadata.key?('exported_response_validation_error')
  end

  def test_rejects_unbound_native_export_diagnostics
    metadata = { 'program_id' => 'example', 'attempt' => 1, 'events_sha256' => 'new' }
    previous = metadata.merge('events_sha256' => 'old', 'exported_response_validation_error' => 'old error')
    assert_raises(RuntimeError) { Fable51Supplement.preserve_native_attempt_diagnostics(metadata, previous) }
  end

  def test_original_method_index_matches_rich_layout_without_duplicate_blobs
    root = File.expand_path('..', __dir__)
    generation = File.join(root, 'batches/20261011-092100/generation')
    rich = JSON.parse(File.read(File.join(generation, 'method-layout-original.json')))
    flat = JSON.parse(File.read(File.join(generation, 'method-layout.json')))
    assert_equal rich.transform_values { |binding| binding.fetch('path') }, flat
    assert_equal 97, flat.size
    rich.each_value do |binding|
      assert_equal binding.fetch('sha256'), E.sha(File.join(root, binding.fetch('path')))
    end
  end
end
