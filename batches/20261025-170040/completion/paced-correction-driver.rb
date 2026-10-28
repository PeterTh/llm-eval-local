# frozen_string_literal: true

# Operational pacing around the immutable source-only proposal runner.
# No changes to model, effort, prompts, review criteria or native execution.
$stdout.sync = true
require_relative "experiment/tools/timing_audit/lib/timing_fix"
scope = ARGV.fetch(0)
raise "Expected trial or full" unless ARGV.size == 1 && %w[trial full].include?(scope)
stage = scope == "trial" ? "pilot" : "full"
campaign = "/home/petert/llm_para_campaigns/20261025-170040-haiku55-opencode-medium/evaluation"
proposals = "/home/petert/llm_timing_fixes/20261028-haiku55-opencode-proposals"
receipt = JSON.parse(File.read(File.join(campaign, "correction-#{stage}-paced-launch.json")))
raise "Pacing driver changed" unless TimingAudit.sha256_file(__FILE__) == receipt.fetch("driver_sha256")
original_driver = File.join(__dir__, "correction-#{stage}-driver.rb")
raise "Original driver changed" unless TimingAudit.sha256_file(original_driver) == receipt.fetch("original_driver_sha256")
gate = JSON.parse(File.read(receipt.fetch("gate_path")))
raise "Gate changed" unless TimingAudit.sha256_file(receipt.fetch("gate_path")) == receipt.fetch("gate_sha256") && gate.fetch("passed")
ids = if scope == "trial"
  File.readlines(File.join(proposals, "trial-ids.txt"), chomp: true).reject(&:empty?)
else
  TimingAudit.load_jsonl(File.join(proposals, "inventory.jsonl")).map { |row| row.fetch("id") }
end
raise "Selection changed" unless ids.sort == receipt.fetch("selected_ids").sort
retained = receipt.fetch("retained_proposals")
retained.each { |path, digest| raise "Retained proposal changed" unless TimingAudit.sha256_file(path) == digest }
phase = "paced_proposals"
active_id = nil
next_request = Time.parse(receipt.fetch("not_before"))
recoveries = []
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(File.join(campaign, "correction-#{stage}-paced-progress.json"), JSON.pretty_generate({
    "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
    "active_id" => active_id, "next_request_not_before" => next_request.utc.iso8601,
    "driver_sha256" => receipt.fetch("driver_sha256"), "scope" => scope,
    "selected" => ids.size, "complete" => ids.count { |id| File.file?(File.join(proposals, "proposals", "#{id}.json")) },
    "rate_limit_recoveries" => recoveries
  }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  ids.each do |id|
    active_id = id
    failures = 0
    loop do
      complete = File.file?(File.join(proposals, "proposals", "#{id}.json"))
      unless complete
        if Time.now < next_request
          phase = "paced_wait"
          checkpoint.call
          puts "Next proposal #{id} not before #{next_request.utc.iso8601}"
          sleep([[next_request - Time.now, 0].max, 30].min) while Time.now < next_request
        end
        next_request = Time.now + 90
      end
      phase = "paced_proposals"
      checkpoint.call
      begin
        TimingFix::ProposalRunner.new(output_dir: proposals, scope: scope, jobs: 1,
          model: "gpt-6.1-sol", effort: "high", retries: 1, only_ids: [id]).run
        break
      rescue StandardError => error
        latest = Dir[File.join(proposals, "logs", id, "attempt-*/metadata.yaml")].max_by { |path| File.basename(File.dirname(path)).delete_prefix("attempt-").to_i }
        metadata = latest && YAML.safe_load_file(latest)
        errors = metadata && metadata.fetch("transport_errors", [])
        temporary_429 = errors && !errors.empty? && errors.all? { |message| message.include?("429 Too Many Requests") } && !metadata["result_sha256"]
        raise unless temporary_429
        failures += 1
        raise "Repeated HTTP 429 after bounded backoff for #{id}: #{error.message}" if failures >= 3
        delay = failures == 1 ? 600 : 1200
        next_request = Time.now + delay
        recoveries << { "program_id" => id, "attempt" => metadata.fetch("attempt"),
          "metadata_sha256" => TimingAudit.sha256_file(latest), "backoff_seconds" => delay,
          "next_request_not_before" => next_request.utc.iso8601 }
        puts "HTTP 429 for #{id}; retain attempt and back off #{delay} seconds"
        checkpoint.call
      end
    end
  end
  retained.each { |path, digest| raise "Accepted proposal changed" unless TimingAudit.sha256_file(path) == digest }
  TimingFix::ProposalVerifier.new(proposals, scope).run
  phase = "resume_original_driver"
  active_id = nil
  checkpoint.call
  load original_driver
  phase = "complete"
  checkpoint.call
rescue Exception => error
  stopped_phase = phase
  phase = "stopped"
  checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
  raise
end
