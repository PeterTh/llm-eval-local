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
end
