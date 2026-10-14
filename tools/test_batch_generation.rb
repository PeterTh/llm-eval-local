# frozen_string_literal: true
require "minitest/autorun"
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
end
