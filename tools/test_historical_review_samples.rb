# frozen_string_literal: true
require "minitest/autorun"
require "open3"
require "rbconfig"

class HistoricalReviewSamplesTest < Minitest::Test
  CHECKER = File.expand_path("../analysis/src/check_opus55_reviews.rb", __dir__)

  def test_source_pinned_archived_comparisons_remain_valid
    output, error, status = Open3.capture3(RbConfig.ruby, CHECKER)
    assert status.success?, error
    assert_includes output, "Opus 5.5 review checks passed"
  end

  def test_altered_archived_samples_are_rejected
    source = File.read(CHECKER)
    original = "samples == peer.fetch('times_ms')"
    assert_equal 1, source.scan(original).size
    changed = source.sub(original, "(archived ? samples.map { |value| value + 1 } : samples) == peer.fetch('times_ms')")
    _, error, status = Open3.capture3(RbConfig.ruby, "-e", "eval(#{changed.inspect}, TOPLEVEL_BINDING, #{CHECKER.inspect})")
    refute status.success?
    assert_includes error, "Changed comparison samples roomsim_claude-sonnet-5-cc-medium_mpi_r5"
  end
end
