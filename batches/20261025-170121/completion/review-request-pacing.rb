# frozen_string_literal: true

# Scheduling adapter around the frozen AuditRunner. Only request concurrency,
# spacing and retries change; the runner's prompts, model, effort, tool bans,
# source/schema checks and result verification are reused unchanged.
require "json"
require "yaml"
require "time"
require "digest"

module BeamReviewPacing
  class YieldForFable < StandardError; end

  class << self
    attr_accessor :next_request, :deadline, :progress_path, :recoveries

    def checkpoint(phase, details = {})
      return unless progress_path
      TimingAudit.atomic_write(progress_path, JSON.pretty_generate({
        "updated_at" => Time.now.utc.iso8601, "pid" => Process.pid,
        "phase" => phase, "next_request_not_before" => next_request&.utc&.iso8601,
        "deadline" => deadline&.utc&.iso8601, "rate_limit_recoveries" => recoveries || []
      }.merge(details)) + "\n")
    end

    def pure_rate_limit_failure?(metadata, events)
      failures = events.select { |event| %w[error turn.failed].include?(event["type"]) }
        .map { |event| event["message"] || event.dig("error", "message") }
      items = events.filter_map { |event| event["item"] }
      metadata["exit_code"] == 1 && !metadata["timed_out"] && !metadata["result_sha256"] &&
        metadata["usage"].nil? && !failures.empty? &&
        failures.all? { |message| message.is_a?(String) && message.include?("429 Too Many Requests") } &&
        items.all? { |item| item["type"] == "error" }
    end

    def wait_for_request(timeout:, details:)
      earliest = [Time.now, next_request || Time.at(0)].max
      if deadline && earliest + timeout + 30 > deadline
        checkpoint("yielded_for_fable_reset", details)
        raise YieldForFable, "No new review started: preserve its full timeout before Fable's reset"
      end
      if Time.now < earliest
        checkpoint("paced_wait", details)
        sleep([earliest - Time.now, 30].min) while Time.now < earliest
      end
      self.next_request = Time.now + 90
      checkpoint("reviewing", details)
    end
  end

  module Dispatch
    def run
      ids = selected_ids
      original_options = [@only_ids, @jobs, @retries]
      retained = ids.filter_map do |id|
        path = result_path(id)
        next unless File.file?(path)
        raise "Existing accepted review is invalid: #{id}" unless valid_existing_result?(id)
        [path, TimingAudit.sha256_file(path)]
      end.to_h
      ids.each do |id|
        next if retained.key?(result_path(id))
        failures = 0
        loop do
          details = { "root" => @output_dir, "scope" => @scope, "active_id" => id,
            "model" => @model, "effort" => @effort, "workers" => 1,
            "selected" => ids.size, "complete" => ids.count { |key| File.file?(result_path(key)) } }
          BeamReviewPacing.wait_for_request(timeout: @timeout, details: details)
          @only_ids, @jobs, @retries = [id], 1, 1
          # AuditRunner normally runs once per object. Reset only its per-call
          # bookkeeping; every failed attempt remains in the immutable logs.
          @failures, @completed_this_run = [], 0
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
            raise "Three consecutive HTTP 429 failures despite pacing for #{id}: #{error.message}" if failures >= 3
            delay = failures == 1 ? 600 : 1200
            BeamReviewPacing.next_request = Time.now + delay
            BeamReviewPacing.recoveries << { "program_id" => id, "root" => @output_dir,
              "attempt" => metadata.fetch("attempt"), "metadata_sha256" => TimingAudit.sha256_file(latest),
              "backoff_seconds" => delay, "next_request_not_before" => BeamReviewPacing.next_request.utc.iso8601 }
            BeamReviewPacing.checkpoint("rate_limit_backoff", details)
          end
        end
      end
      retained.each { |path, sha| raise "Accepted review changed: #{path}" unless TimingAudit.sha256_file(path) == sha }
      TimingAudit::AuditVerifier.new(@output_dir, @scope).run if ids.sort == scope_ids.sort
    ensure
      @only_ids, @jobs, @retries = original_options if original_options
    end
  end
end
