# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "review-request-pacing"

class ReviewRequestPacingTest < Minitest::Test
  def setup
    @metadata = { "exit_code" => 1, "timed_out" => false, "usage" => nil }
    @events = [
      { "type" => "thread.started" },
      { "type" => "item.completed", "item" => { "type" => "error", "message" => "Tool host deliberately disabled" } },
      { "type" => "error", "message" => "exceeded retry limit, last status: 429 Too Many Requests" },
      { "type" => "turn.failed", "error" => { "message" => "exceeded retry limit, last status: 429 Too Many Requests" } }
    ]
    BeamReviewPacing.progress_path = nil
  end

  def test_accepts_only_pre_output_rate_limit_failure
    assert BeamReviewPacing.pure_rate_limit_failure?(@metadata, @events)
    refute BeamReviewPacing.pure_rate_limit_failure?(@metadata.merge("usage" => {}), @events)
    refute BeamReviewPacing.pure_rate_limit_failure?(@metadata.merge("result_sha256" => "accepted"), @events)
    refute BeamReviewPacing.pure_rate_limit_failure?(@metadata.merge("timed_out" => true), @events)
    refute BeamReviewPacing.pure_rate_limit_failure?(@metadata, [])
  end

  def test_rejects_output_tools_and_other_failures
    %w[agent_message reasoning command_execution].each do |type|
      refute BeamReviewPacing.pure_rate_limit_failure?(@metadata, @events + [{ "type" => "item.completed", "item" => { "type" => type } }])
    end
    refute BeamReviewPacing.pure_rate_limit_failure?(@metadata, @events + [{ "type" => "error", "message" => "Authentication failed" }])
  end

  def test_reserves_complete_request_timeout_before_reset_without_waiting
    BeamReviewPacing.next_request = Time.now + 600
    BeamReviewPacing.deadline = Time.now + 1200
    assert_raises(BeamReviewPacing::YieldForFable) { BeamReviewPacing.wait_for_request(timeout: 900, details: {}) }
  end

  def test_dispatch_preserves_model_and_selection_with_fresh_per_call_state
    base = Class.new do
      attr_reader :calls
      def initialize(root)
        @output_dir, @scope, @timeout = root, "trial", 900
        @model, @effort = "gpt-5.6-luna", "high"
        @only_ids, @jobs, @retries = %w[one two], 4, 3
        @failures, @calls = [:old_call], []
      end
      def run
        raise "Stale per-call failure state" unless @failures.empty?
        @calls << [@only_ids.dup, @jobs, @retries, @model, @effort]
        @failures << :completed_call_marker
      end
      def selected_ids = @only_ids
      def scope_ids = %w[one two three]
      def result_path(id) = File.join(@output_dir, id + ".json")
      def options = [@only_ids, @jobs, @retries]
    end
    base.prepend(BeamReviewPacing::Dispatch)
    Dir.mktmpdir("beam-pacing-test-") do |root|
      runner = base.new(root)
      BeamReviewPacing.stub(:wait_for_request, ->(**_options) {}) { runner.run }
      assert_equal [[%w[one], 1, 1, "gpt-5.6-luna", "high"], [%w[two], 1, 1, "gpt-5.6-luna", "high"]], runner.calls
      assert_equal [%w[one two], 4, 3], runner.options
    end
  end
end
