# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "digest"
require "fileutils"
require_relative "correction-request-pacing"

module TimingAudit
  def self.sha256_file(path) = Digest::SHA256.file(path).hexdigest
end

class CorrectionRequestPacingTest < Minitest::Test
  def setup
    BeamReviewPacing.progress_path = nil
    BeamReviewPacing.recoveries = []
  end

  def runner_class
    Class.new do
      attr_reader :calls, :verified
      def initialize(root, ids: %w[one two], retained_valid: true, failure_type: nil)
        @output_dir, @scope, @timeout = root, "full", 900
        @model, @effort = "gpt-6.1-sol", "high"
        @only_ids, @jobs, @retries = [], 16, 3
        @ids, @retained_valid, @calls = ids, retained_valid, []
        @failure_type = failure_type
      end
      def run
        raise "Stale state" unless @failures.empty? && @completed == 0 && @completed_this_run == 0
        @calls << [@only_ids.dup, @jobs, @retries, @model, @effort]
        if @failure_type
          attempt = @calls.size
          folder = File.join(@output_dir, "logs", @only_ids.first, format("attempt-%02d", attempt))
          FileUtils.mkdir_p(folder)
          metadata = { "attempt" => attempt, "exit_code" => 1, "timed_out" => false, "usage" => nil }
          events = [{ "type" => "error", "message" => "429 Too Many Requests" }]
          events << { "type" => "item.completed", "item" => { "type" => "reasoning", "text" => "partial work" } } if @failure_type == :partial
          File.write(File.join(folder, "metadata.yaml"), YAML.dump(metadata))
          File.write(File.join(folder, "events.jsonl"), events.map { |event| JSON.generate(event) + "\n" }.join)
          raise "Simulated transport failure"
        end
        @failures << :last_call
      end
      def selected_ids = @only_ids.empty? ? @ids : @only_ids
      def scope_ids = @ids
      def paced_path(id) = File.join(@output_dir, id + ".json")
      def paced_validator = :valid_existing?
      def valid_existing?(_id) = @retained_valid
      def paced_verify = (@verified = true)
      def options = [@only_ids, @jobs, @retries]
      prepend BeamCorrectionPacing::Dispatch
    end
  end

  def test_one_request_at_a_time_preserves_selection_model_and_verifier
    Dir.mktmpdir("beam-correction-pacing-") do |root|
      runner = runner_class.new(root)
      BeamReviewPacing.stub(:wait_for_request, ->(**_) {}) { runner.run }
      assert_equal [[%w[one], 1, 1, "gpt-6.1-sol", "high"], [%w[two], 1, 1, "gpt-6.1-sol", "high"]], runner.calls
      assert runner.verified
      assert_equal [[], 16, 3], runner.options
    end
  end

  def test_accepted_result_is_reused_without_request
    Dir.mktmpdir("beam-correction-pacing-") do |root|
      File.write(File.join(root, "one.json"), "accepted")
      runner = runner_class.new(root)
      BeamReviewPacing.stub(:wait_for_request, ->(**_) {}) { runner.run }
      assert_equal [%w[two]], runner.calls.map(&:first)
      assert_equal "accepted", File.read(File.join(root, "one.json"))
      assert runner.verified
    end
  end

  def test_invalid_retained_response_stops_instead_of_retrying
    Dir.mktmpdir("beam-correction-pacing-") do |root|
      File.write(File.join(root, "one.json"), "invalid")
      runner = runner_class.new(root, retained_valid: false)
      assert_raises(RuntimeError) { runner.run }
      assert_empty runner.calls
    end
  end

  def test_empty_adjudication_selection_still_emits_verified_summary
    Dir.mktmpdir("beam-correction-pacing-") do |root|
      runner = runner_class.new(root, ids: [])
      runner.run
      assert_empty runner.calls
      assert runner.verified
    end
  end

  def test_rate_limit_recovery_is_bounded_and_preserves_failed_attempts
    Dir.mktmpdir("beam-correction-pacing-") do |root|
      runner = runner_class.new(root, ids: %w[one], failure_type: :pre_output)
      BeamReviewPacing.stub(:wait_for_request, ->(**_) {}) do
        assert_raises(RuntimeError) { runner.run }
      end
      assert_equal 3, runner.calls.size
      assert_equal [600, 1200], BeamReviewPacing.recoveries.map { |r| r.fetch("backoff_seconds") }
      assert_equal 3, Dir[File.join(root, "logs/one/attempt-*/metadata.yaml")].size
      assert_equal [[], 16, 3], runner.options
    end
  end

  def test_rate_limit_after_reasoning_is_not_retried
    Dir.mktmpdir("beam-correction-pacing-") do |root|
      runner = runner_class.new(root, ids: %w[one], failure_type: :partial)
      BeamReviewPacing.stub(:wait_for_request, ->(**_) {}) do
        assert_raises(RuntimeError) { runner.run }
      end
      assert_equal 1, runner.calls.size
      assert_empty BeamReviewPacing.recoveries
    end
  end
end
