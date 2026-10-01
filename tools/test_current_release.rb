# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "current_release"

class CurrentReleaseTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  class TamperedRelease < CurrentRelease
    def initialize(root, &mutation)
      super(root)
      @mutation = mutation
    end
    def load_records(pattern)
      records = super
      @mutation.call(records) if pattern.start_with?("batches/") && pattern.include?("benchmark/records")
      records
    end
  end

  def test_score_boundaries_and_unsuccessful_measurements
    cell = { "fastest" => 1.0, "top" => 2.0, "great" => 3.0, "good" => 4.0 }
    row = { "validation_status" => "5", "benchmark_success" => "true" }
    [1, 2, 3, 4, 5].zip([10, 9, 8, 7, 6]).each do |time, expected|
      assert_equal expected, CurrentRelease.score(row.merge("benchmark_median_time" => time.to_s), cell)
    end
    assert_equal 5, CurrentRelease.score(row.merge("benchmark_success" => "false"), cell)
    assert_equal 2, CurrentRelease.score(row.merge("validation_status" => "2", "benchmark_success" => ""), cell)
  end

  def test_checked_in_outputs_and_every_winner_review_reconstruct
    assert_output(/Current release verified/) { CurrentRelease.new(ROOT).run(check: true, require_reviews: true) }
  end

  def test_rejects_modified_timing_correction_commit
    release = TamperedRelease.new(ROOT) do |records|
      record = records.values.find { |r| r.fetch("timing_fixed") }
      record.fetch("timing_correction").fetch("corrected_source")["commit"] = "0" * 40
    end
    assert_match(/correction source differs/, assert_raises(RuntimeError) { release.build }.message)
  end

  def test_rejects_modified_measured_vector
    release = TamperedRelease.new(ROOT) do |records|
      record = records.values.find { |r| r.fetch("success") }
      record.fetch("metrics").first["time"] *= 2
    end
    assert_match(/measurement vector mismatch/, assert_raises(RuntimeError) { release.build }.message)
  end

  def test_rejects_modified_benchmark_configuration
    release = TamperedRelease.new(ROOT) { |records| records.values.first["configuration_sha256"] = "0" * 64 }
    assert_match(/configuration mismatch/, assert_raises(RuntimeError) { release.build }.message)
  end

  def test_rejects_paths_outside_release
    release = CurrentRelease.new(ROOT)
    assert_raises(RuntimeError) { release.path("../outside") }
    assert_raises(RuntimeError) { release.path("/tmp/outside") }
  end

  def test_usage_overlay_changes_only_token_metadata_and_requires_coverage
    record = JSON.parse(File.open(File.join(ROOT, "metadata/codex-usage/20260805-120633.jsonl"), &:readline))
    bench, model, backend, repetition = record.fetch("run_id").split("_")
    original = {"benchmark" => bench, "model" => model, "par_type" => backend,
                "run" => repetition.delete_prefix("r"), "source_batch" => record.fetch("batch"),
                "total_tokens" => record.fetch("legacy_reported_tokens").to_s,
                "benchmark_times" => "1;2;3;4;5", "overall_score" => "9"}
    Dir.mktmpdir("usage-overlay-") do |directory|
      File.write(File.join(directory, "usage.jsonl"), JSON.generate(record) + "\n")
      release = CurrentRelease.allocate
      release.instance_variable_set(:@root, directory)
      release.instance_variable_set(:@catalog, {"codex_usage_overlays" => [
        {"path" => "usage.jsonl", "batch" => record.fetch("batch"), "expected_runs" => 1}]})
      row = original.dup
      release.apply_codex_usage!([row], [], {})
      assert_equal record.fetch("usage").fetch("total_tokens").to_s, row["total_tokens"]
      assert_equal original["total_tokens"], row["legacy_reported_tokens"]
      assert_equal original["benchmark_times"], row["benchmark_times"]
      assert_equal original["overall_score"], row["overall_score"]
      assert_raises(RuntimeError) { release.apply_codex_usage!([], [], {}) }
      assert_raises(RuntimeError) { release.apply_codex_usage!([original.merge("total_tokens" => "1")], [], {}) }
    end
  end
end
