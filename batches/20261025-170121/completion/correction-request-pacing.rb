# frozen_string_literal: true

# Reuse the audit's one-worker, 90-second scheduler and strictly pre-output-429
# recovery for the three existing correction runners. The frozen runners still
# build and validate every request, response and source binding themselves.
require_relative "review-request-pacing"

module BeamCorrectionPacing
  module Dispatch
    def run
      ids = selected_ids
      original_options = [@only_ids, @jobs, @retries]
      retained = ids.filter_map do |id|
        path = paced_path(id)
        next unless File.file?(path)
        raise "Invalid retained correction response: #{id}" unless send(paced_validator, id)
        [path, TimingAudit.sha256_file(path)]
      end.to_h
      ids.each do |id|
        next if retained.key?(paced_path(id))
        failures = 0
        loop do
          details = { "root" => @output_dir, "scope" => @scope, "active_id" => id,
            "model" => @model, "effort" => @effort, "workers" => 1,
            "selected" => ids.size, "complete" => ids.count { |key| File.file?(paced_path(key)) } }
          BeamReviewPacing.wait_for_request(timeout: @timeout, details: details)
          @only_ids, @jobs, @retries = [id], 1, 1
          @failures, @completed_this_run, @completed = [], 0, 0
          begin
            super
            break
          rescue StandardError => error
            latest = Dir[File.join(@output_dir, "logs", id, "attempt-*/metadata.yaml")]
              .max_by { |path| File.basename(File.dirname(path)).delete_prefix("attempt-").to_i }
            metadata = latest && YAML.safe_load_file(latest)
            events_path = latest && File.join(File.dirname(latest), "events.jsonl")
            events = events_path && File.readlines(events_path).map { |line| JSON.parse(line) }
            raise unless metadata && events && BeamReviewPacing.pure_rate_limit_failure?(metadata, events)
            failures += 1
            raise "Three consecutive pre-output HTTP 429 failures for #{id}: #{error.message}" if failures >= 3
            delay = failures == 1 ? 600 : 1200
            BeamReviewPacing.next_request = Time.now + delay
            BeamReviewPacing.recoveries << { "program_id" => id, "root" => @output_dir,
              "attempt" => metadata.fetch("attempt"), "metadata_sha256" => TimingAudit.sha256_file(latest),
              "backoff_seconds" => delay, "next_request_not_before" => BeamReviewPacing.next_request.utc.iso8601 }
            BeamReviewPacing.checkpoint("rate_limit_backoff", details)
          end
        end
      end
      retained.each { |path, sha| raise "Accepted response changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
      paced_verify if ids.sort == scope_ids.sort
    ensure
      @only_ids, @jobs, @retries = original_options if original_options
    end
  end

  module Proposal
    include Dispatch
    def paced_path(id) = proposal_path(id)
    def paced_validator = :valid_existing_proposal?
    def paced_verify = TimingFix::ProposalVerifier.new(@output_dir, @scope).run
  end

  module Review
    include Dispatch
    def paced_path(id) = result_path(id)
    def paced_validator = :valid_existing_result?
    def paced_verify = TimingFixReview::Verifier.new(@output_dir, @scope).run
  end

  module Adjudication
    include Dispatch
    def paced_path(id) = result_path(id)
    def paced_validator = :valid_existing?
    def paced_verify = TimingFixAdjudication::Verifier.new(@output_dir, @scope).run
  end
end
