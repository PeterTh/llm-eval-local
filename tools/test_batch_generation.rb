# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "current_release"

class BatchGenerationTest < Minitest::Test
  def setup
    @release = CurrentRelease.allocate
    @campaign = { "id" => "20261006-204623" }
    @record = { "batch" => @campaign.fetch("id"), "session_id" => "session", "session_cwd" => "/batch/run",
      "cli_version" => "0.160.1", "transcript_sha256" => "a" * 64, "legacy_reported_tokens" => 30,
      "source" => CodexUsage::SOURCE, "usage" => { "input_tokens" => 100, "cached_input_tokens" => 80,
        "output_tokens" => 10, "total_tokens" => 110, "reasoning_output_tokens" => 7 } }
    @observation = { "id" => "example", "session_id" => "session", "session_cwd" => "/batch/run",
      "version" => "0.160.1", "sha256" => { "output.txt" => "a" * 64 }, "legacy_reported_tokens" => 30,
      "model" => "gpt-6.1-sol", "reasoning_effort" => "medium", "total_seconds" => 42.5 }
    @row = { "model" => "gpt-6.1-sol-medium", "input_tokens" => "100", "cached_tokens" => "80",
      "output_tokens" => "10", "total_tokens" => "110", "reasoning_output_tokens" => "7",
      "cache_write_input_tokens" => nil, "legacy_reported_tokens" => "30", "total_time" => "42.5", "api_time" => nil,
      "token_usage_source" => CodexUsage::SOURCE, "token_usage_session_id" => "session" }
  end

  def verify
    @release.verify_generation_observations!(@campaign, [@observation], { "example" => @row }, usage: { "example" => @record })
  end

  def test_exact_counters_and_missing_optional_counter_are_retained
    verify
    @row["cache_write_input_tokens"] = "0"
    assert_match(/counter differs/, assert_raises(RuntimeError) { verify }.message)
  end

  def test_rejects_counter_and_transcript_changes
    @row["cached_tokens"] = "79"
    assert_match(/counter differs/, assert_raises(RuntimeError) { verify }.message)
    @row["cached_tokens"] = "80"
    @observation.fetch("sha256")["output.txt"] = "b" * 64
    assert_match(/identity differs/, assert_raises(RuntimeError) { verify }.message)
  end

  def test_rejects_unmatched_session_or_scope
    @row["token_usage_session_id"] = "another"
    assert_match(/provenance differs/, assert_raises(RuntimeError) { verify }.message)
    assert_match(/scope differs/, assert_raises(RuntimeError) {
      @release.verify_generation_observations!(@campaign, [@observation], {}, usage: {})
    }.message)
  end

  def test_claude_observation_accounting_is_unchanged
    observation = { "id" => "claude", "inclusive_input_tokens" => 100, "token_counts" => {
      "cache_read_input_tokens" => 80, "output_tokens" => 10 }, "total_tokens" => 110,
      "api_seconds" => 20.0, "total_seconds" => 42.5 }
    row = @row.merge("api_time" => "20.0")
    @release.verify_generation_observations!(@campaign, [observation], { "claude" => row })
    row["total_tokens"] = "111"
    assert_match(/counter differs/, assert_raises(RuntimeError) {
      @release.verify_generation_observations!(@campaign, [observation], { "claude" => row })
    }.message)
  end

  def opencode_fixture
    campaign = { 'id' => '20261017-192226', 'generation_harness' => 'opencode', 'source_commit' => 'b' * 40 }
    counts = { 'input_tokens' => 100, 'cached_input_tokens' => 80, 'cache_write_input_tokens' => 0,
      'output_tokens' => 10, 'reasoning_output_tokens' => 7, 'total_tokens' => 110 }
    observation = { 'id' => 'example', 'model' => 'openai/gpt-6.1-sol', 'reasoning_effort' => 'medium',
      'session_id' => 'session', 'outcome' => 'completed', 'usage_available' => true, 'usage_complete' => true,
      'usage_source' => 'opencode_native_step_finish', 'token_counts' => counts, 'total_tokens' => 110,
      'raw_total_seconds' => 44.5, 'total_seconds' => 42.5, 'retry_backoff_seconds' => 2.0, 'retry_count' => 1,
      'sha256' => %w[output.txt timing.txt instruction.txt process-status.txt opencode-config.txt opencode-session.txt opencode-events.txt opencode-process.txt].to_h { |name| [name, 'a' * 64] } }
    row = @row.merge('model' => 'gpt-6.1-sol-oc-medium', 'token_usage_source' => 'opencode_native_step_finish',
      'cache_write_input_tokens' => '0', 'legacy_reported_tokens' => nil,
      'raw_total_time' => '44.5', 'agent_retry_backoff_seconds' => '2.0', 'agent_retry_count' => '1')
    [campaign, observation, row]
  end

  def test_opencode_exact_usage_retry_subtraction_and_unknown_api_time
    campaign, observation, row = opencode_fixture
    check = ->(candidate) { @release.verify_generation_observations!(campaign, [observation], { 'example' => candidate }) }
    check.call(row)
    %w[input_tokens cached_tokens output_tokens reasoning_output_tokens cache_write_input_tokens raw_total_time agent_retry_backoff_seconds agent_retry_count].each do |field|
      assert_raises(RuntimeError, field) { check.call(row.merge(field => (Float(row.fetch(field)) + 1).to_s)) }
    end
    assert_raises(RuntimeError) { check.call(row.merge('api_time' => '0')) }
    assert_raises(RuntimeError) { check.call(row.merge('token_usage_session_id' => 'another')) }
    observation['usage_complete'] = false
    assert_raises(RuntimeError) { check.call(row) }
  end

  def test_opencode_rejects_inconsistent_inclusive_counts_and_retry_clock
    campaign, observation, row = opencode_fixture
    check = -> { @release.verify_generation_observations!(campaign, [observation], { 'example' => row }) }
    observation.fetch('token_counts')['cached_input_tokens'] = 101
    assert_raises(RuntimeError) { check.call }
    observation.fetch('token_counts')['cached_input_tokens'] = 80
    observation['total_seconds'] = 44.5
    assert_raises(RuntimeError) { check.call }
  end

  def test_opencode_context_is_bound_to_sessions_and_exact_usage
    campaign, observation, = opencode_fixture
    record = { 'id' => 'example', 'session_id' => 'session', 'native_session_sha256' => 'a' * 64,
      'token_counts' => observation.fetch('token_counts').dup, 'request_count' => 2,
      'maximum_request_input_tokens' => 60, 'requests_above_272000_tokens' => 0, 'cache_write_input_tokens' => 0 }
    context = { 'schema_version' => 1, 'source_batch' => campaign.fetch('id'), 'source_commit' => campaign.fetch('source_commit'),
      'programs' => 1, 'requests' => 2, 'maximum_request_input_tokens' => 60,
      'requests_above_272000_tokens' => 0, 'cache_write_input_tokens' => 0, 'records' => [record] }
    check = -> { @release.verify_opencode_context!(campaign, [observation], context) }
    check.call
    record['native_session_sha256'] = 'c' * 64
    assert_raises(RuntimeError) { check.call }
    record['native_session_sha256'] = 'a' * 64
    record['maximum_request_input_tokens'] = 49
    assert_raises(RuntimeError) { check.call }
    record['maximum_request_input_tokens'] = 60
    context['requests'] = 3
    assert_raises(RuntimeError) { check.call }
  end

  def test_context_usage_binds_original_observation_and_counter_totals
    counts = { 'input_tokens' => 20, 'cache_read_input_tokens' => 80,
      'cache_creation_input_tokens' => 10, 'output_tokens' => 10 }
    observation = @observation.merge('model' => 'claude-haiku-5-5', 'token_counts' => counts)
    campaign = @campaign.merge('source_commit' => 'b' * 40)
    short = { 'input_tokens' => 20, 'cache_read_input_tokens' => 80, 'cache_creation_5m_tokens' => 0,
      'cache_creation_1h_tokens' => 10, 'output_tokens' => 10, 'inclusive_input_tokens' => 110,
      'requests' => 1, 'max_request_input_tokens' => 110, 'streamed_output_lower_bound' => 1 }
    record = { 'id' => observation.fetch('id'), 'schema_version' => 1,
      'source_batch' => campaign.fetch('id'), 'source_commit' => campaign.fetch('source_commit'),
      'session_id' => observation.fetch('session_id'), 'model' => observation.fetch('model'),
      'claude_code_version' => observation.fetch('version'), 'transcript_sha256' => 'a' * 64,
      'native_token_counts' => counts, 'bands' => { 'short' => short, 'long' => short.transform_values { 0 } },
      'requests' => 1, 'request_input_threshold_tokens' => 100000,
      'output_band_evidence' => 'native_total_in_single_observed_band', 'per_request_output_available' => false }
    @release.verify_context_observations!(campaign, [observation], [record])
    assert_match(/identity differs/, assert_raises(RuntimeError) {
      @release.verify_context_observations!(campaign, [observation], [record.merge('source_commit' => 'c' * 40)])
    }.message)
    short['output_tokens'] = 9
    assert_match(/counters differ/, assert_raises(RuntimeError) {
      @release.verify_context_observations!(campaign, [observation], [record])
    }.message)
  end

  def test_generation_recovery_binds_native_duration_and_unknown_wrapper_status
    Dir.mktmpdir('generation-recovery-test-') do |root|
      @release.instance_variable_set(:@root, root)
      observation = @observation.merge('model' => 'claude-sonnet-5-5', 'version' => '2.1.296',
        'total_seconds' => 865.229, 'generation_time_source' => 'claude_result_duration_ms',
        'generation_time_recovered' => true, 'wrapper_exit_status_available' => false,
        'sha256' => %w[output.txt timing.txt instruction.txt process-status.txt].to_h { |name| [name, 'a' * 64] })
      receipt = observation.slice('model', 'session_id', 'version', 'generation_time_source', 'generation_time_recovered', 'wrapper_exit_status_available').merge(
        'schema_version' => 1, 'run_id' => 'example', 'campaign_id' => @campaign.fetch('id'),
        'approved_by' => 'user', 'decision' => 'retain_completed_native_result', 'duration_ms' => 865229,
        'wrapper_wall_time_seconds' => nil, 'wrapper_start_time' => nil, 'wrapper_end_time' => nil,
        'metadata_sha256' => observation.fetch('sha256').dup)
      row = { 'generation_time_recovered' => 'true', 'generation_time_source' => 'claude_result_duration_ms', 'wrapper_exit_status_available' => 'false' }
      file = File.join(root, "batches/#{@campaign.fetch('id')}/generation/recoveries/example.json")
      FileUtils.mkdir_p(File.dirname(file))
      retain = lambda do |record|
        File.write(file, JSON.generate(record))
        digest = Digest::SHA256.file(file).hexdigest
        observation['generation_recovery_sha256'] = digest
        observation.fetch('sha256')['generation-recovery.txt'] = digest
        row['generation_recovery_sha256'] = digest
      end
      retain.call(receipt)
      @release.verify_generation_recovery!(@campaign, observation, row)
      assert_raises(RuntimeError) { @release.verify_generation_recovery!(@campaign, observation, row.merge('generation_time_recovered' => 'false')) }
      assert_raises(RuntimeError) { @release.verify_generation_recovery!(@campaign, observation, row.merge('wrapper_exit_status_available' => 'true')) }
      File.write(file, File.read(file) + "\n")
      assert_match(/receipt changed/, assert_raises(RuntimeError) { @release.verify_generation_recovery!(@campaign, observation, row) }.message)
      [receipt.merge('duration_ms' => 865230), receipt.merge('wrapper_start_time' => 'invented'),
       receipt.merge('approved_by' => 'unknown'), receipt.merge('session_id' => 'another'),
       receipt.merge('metadata_sha256' => receipt.fetch('metadata_sha256').merge('output.txt' => 'b' * 64))].each do |changed|
        retain.call(changed)
        assert_raises(RuntimeError) { @release.verify_generation_recovery!(@campaign, observation, row) }
      end
    end
  end

  def test_rejects_recovery_metadata_without_a_recovery_flag
    assert_raises(RuntimeError) do
      @release.verify_generation_recovery!(@campaign, @observation, @row.merge('generation_time_source' => 'claude_result_duration_ms'))
    end
  end
end
