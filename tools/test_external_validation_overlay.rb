# frozen_string_literal: true

require "minitest/autorun"
require_relative "current_release"

class ExternalValidationOverlayTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def setup
    reader = CurrentRelease.new(ROOT)
    @overlay = reader.instance_variable_get(:@external)
    @rows = @overlay.applied_ids.map do |id|
      record = @overlay.registry.records.fetch(id)
      benchmark, model, backend, repetition = id.split("_")
      { "benchmark" => benchmark, "model" => model, "par_type" => backend, "run" => repetition.delete_prefix("r"),
        "source_path" => record.fetch("source_path"), "validation_status" => "5", "benchmark_success" => "true",
        "benchmark_times" => "1;2;3;4;5", "benchmark_median_time" => "3", "benchmark_wall_times" => "6;6;6;6;6",
        "timing_fixed" => "true", "original_source_commit" => "preserved-original" }
    end
    @benchmarks = @overlay.applied_ids.to_h { |id| [id, { "success" => true }] }
    @sources = @overlay.registry.records.transform_values { |record| record.fetch("source_commit") }
  end

  def test_external_failures_remove_only_effective_timings_preserving_source_history
    archived = Marshal.load(Marshal.dump(@benchmarks))
    headers = @rows.first.keys
    inputs = {}
    @overlay.apply!(@rows, @benchmarks, @sources, headers, inputs)
    assert_empty @benchmarks
    assert_equal @overlay.applied_ids.size, archived.size
    @rows.each do |row|
      assert_equal "4", row.fetch("validation_status")
      assert_nil row.fetch("benchmark_success")
      assert_nil row.fetch("benchmark_median_time")
      assert_nil row.fetch("benchmark_times")
      assert_equal "true", row.fetch("timing_fixed")
      assert_equal "preserved-original", row.fetch("original_source_commit")
      assert_includes row.fetch("validation_err_string"), "Output comparison FAILED"
    end
    assert_includes headers, "external_validation_case"
    assert inputs.keys.any? { |path| path.end_with?("records.jsonl") }
  end

  def test_rejects_different_effective_source
    @sources[@overlay.applied_ids.first] = "0" * 40
    assert_match(/effective source/, assert_raises(RuntimeError) { @overlay.apply!(@rows, @benchmarks, @sources, [], {}) }.message)
  end

  def test_rejects_prior_failure_or_omitted_disposition
    @rows.first["validation_status"] = "3"
    assert_match(/prior status/, assert_raises(RuntimeError) { @overlay.apply!(@rows, @benchmarks, @sources, [], {}) }.message)
    @rows.pop
    assert_match(/coverage/, assert_raises(RuntimeError) { @overlay.apply!(@rows, @benchmarks, @sources, [], {}) }.message)
  end
end
