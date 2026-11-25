# frozen_string_literal: true
require "minitest/autorun"
require_relative "winner-review-context"

class Gpt62WinnerContextTest < Minitest::Test
  def row(id, times, cell = "example/mpi", model = "old")
    Gpt62WinnerContext.entry(id: id, cell: cell, times: times, model: model)
  end

  def test_median_and_sample_range
    result = row("old", [3, 100, 1, 4, 2])
    assert_equal 3, result.fetch("median_ms")
    assert_equal [1, 100], result.fetch("range_ms")
  end

  def test_new_winner_and_close_group
    result = Gpt62WinnerContext.compare([row("old", [100, 102, 101, 100, 101])],
      [row("new", [91, 90, 91, 92, 91], "example/mpi", "new")]).fetch("example/mpi")
    assert result.fetch("new_winner")
    assert_equal "new", result.fetch("current").fetch("id")
    assert_equal "old", result.fetch("previous").fetch("id")
    assert_equal 2, result.fetch("top").size
    assert_equal "new", result.fetch("new_profiles").fetch("new").fetch("id")
  end

  def test_no_new_winner_and_deterministic_tie
    result = Gpt62WinnerContext.compare([row("a-old", [10] * 5)],
      [row("z-new", [10] * 5, "example/mpi", "new")]).fetch("example/mpi")
    refute result.fetch("new_winner")
    assert_equal "a-old", result.fetch("current").fetch("id")
  end

  def test_invalid_vectors_duplicates_and_new_cells_fail_closed
    assert_raises(RuntimeError) { row("bad", [1, 2, 3]) }
    assert_raises(RuntimeError) { row("bad", [1, 2, 3, 4, Float::INFINITY]) }
    assert_raises(RuntimeError) { row("bad", [0, 1, 2, 3, 4]) }
    old = row("old", [1] * 5)
    assert_raises(RuntimeError) { Gpt62WinnerContext.groups([old, old]) }
    assert_raises(RuntimeError) { Gpt62WinnerContext.compare([old], [row("new", [2] * 5, "other/mpi", "new")]) }
  end

  def test_historical_source_batches_use_canonical_records_and_replacements_take_precedence
    canonical = { "id" => "2026-08-timing-corrected", "validation_format" => "canonical" }
    newer = { "id" => "new-batch", "validation_format" => "batch" }
    replacement = { "id" => "new-batch", "ids" => ["replaced"] }
    catalog = { "campaigns" => [canonical, newer], "observation_replacements" => [replacement] }
    %w[20260215-162417 20260805-120633].each do |batch|
      assert_equal canonical, Gpt62WinnerContext.historical_campaign(catalog, batch, "legacy")
    end
    assert_equal newer, Gpt62WinnerContext.historical_campaign(catalog, "new-batch", "untouched")
    assert_equal replacement, Gpt62WinnerContext.historical_campaign(catalog, "new-batch", "replaced")
    assert_raises(RuntimeError) do
      Gpt62WinnerContext.historical_campaign({ "campaigns" => [] }, "unknown", "unknown")
    end
  end
end
