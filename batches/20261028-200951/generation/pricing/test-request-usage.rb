# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "read-request-usage"

class TerraRequestUsageTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("terra-request-usage-test-", "/tmp")
    @path = File.join(@root, "session.jsonl")
    @id = "00000000-0000-4000-8000-000000000001"
    @cwd = "/home/llmtest/evals/20261028-200951/black-scholes_gpt-6.1-terra-medium_omp_r1"
    @one = { "input_tokens" => 10, "cached_input_tokens" => 8, "output_tokens" => 2,
      "total_tokens" => 12, "reasoning_output_tokens" => 1, "cache_write_input_tokens" => 0 }
    @two = { "input_tokens" => 12, "cached_input_tokens" => 4, "output_tokens" => 3,
      "total_tokens" => 15, "reasoning_output_tokens" => 0, "cache_write_input_tokens" => 0 }
    @total = @one.to_h { |key, value| [key, value + @two.fetch(key)] }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def event(kind, payload)
    { "timestamp" => "2026-10-29T01:00:00Z", "type" => kind, "payload" => payload }
  end

  def native(response, usage, total)
    event("token_usage_record", { "response_id" => response, "usage" => usage, "thread_token_usage" => total })
  end

  def record(extra: [], second_usage: @two, expected_total: @total)
    rows = [event("session_meta", { "id" => @id, "cwd" => @cwd, "cli_version" => "0.160.1" }),
      native("first", @one, @one), *extra, native("second", second_usage, @total),
      event("event_msg", { "type" => "token_count", "info" => { "total_token_usage" => @total, "last_token_usage" => @two, "model_context_window" => 475000 } }),
      event("event_msg", { "type" => "task_complete" })]
    File.write(@path, rows.map { |row| JSON.generate(row) + "\n" }.join)
    { "schema_version" => 1, "source" => CodexUsage::SOURCE, "batch" => "20261028-200951",
      "run_id" => File.basename(@cwd), "session_id" => @id, "cli_version" => "0.160.1",
      "session_path" => "session.jsonl", "session_cwd" => @cwd, "session_sha256" => Digest::SHA256.file(@path).hexdigest,
      "transcript_sha256" => "a" * 64, "token_count_timestamp" => "now", "task_completed_at" => "now",
      "usage" => expected_total, "legacy_reported_tokens" => expected_total.fetch("total_tokens") - expected_total.fetch("cached_input_tokens") }
  end

  def test_exact_request_sums_and_independent_stream
    result = TerraRequestUsage.recover(record, sessions_root: @root)
    assert_equal 2, result.fetch("request_count")
    assert_equal 12, result.fetch("max_request_input_tokens")
    assert_equal @total, result.fetch("total_usage")
  end

  def test_identical_duplicate_is_not_double_counted
    result = TerraRequestUsage.recover(record(extra: [native("first", @one, @one)]), sessions_root: @root)
    assert_equal 2, result.fetch("request_count")
    assert_equal 1, result.fetch("duplicate_records_ignored")
  end

  def test_conflicting_duplicate_is_rejected
    assert_raises(RuntimeError) { TerraRequestUsage.recover(record(extra: [native("first", @two, @one)]), sessions_root: @root) }
  end

  def test_missing_optional_counter_is_not_fabricated_as_zero
    assert_raises(RuntimeError) { TerraRequestUsage.recover(record(second_usage: @two.reject { |key, _| key == "cache_write_input_tokens" }), sessions_root: @root) }
  end

  def test_bound_hash_is_verified
    value = record
    value["session_sha256"] = "b" * 64
    assert_raises(RuntimeError) { TerraRequestUsage.recover(value, sessions_root: @root) }
  end

  def test_mismatching_final_totals_are_rejected
    assert_raises(RuntimeError) { TerraRequestUsage.recover(record(expected_total: @one), sessions_root: @root) }
  end
end
