# frozen_string_literal: true

$stdout.sync = true
require "/tmp/haiku55-evaluation-20261014.ZqhO2v/experiment/tools/timing_audit/lib/qtclustering_boundary"
campaign = "/home/petert/llm_para_campaigns/20261012-111947-haiku55-medium/evaluation"
boundary = "/home/petert/llm_timing_audit/20261014-haiku55-qtclustering"
review = "#{boundary}-sol61"
evidence = File.join(campaign, "review-provider-recovery")
mode = ARGV.fetch(0)
if mode == "prepare"
  raise "Recovery already prepared" if File.exist?(evidence)
  progress_path = File.join(campaign, "audit-pilot-progress.json")
  stopped = JSON.parse(File.read(progress_path))
  raise "Unexpected stopped phase" unless stopped["phase"] == "stopped" && stopped["stopped_phase"] == "qtclustering_pilot_sol61"
  ids = File.readlines(File.join(review, "trial-ids.txt"), chomp: true)
  accepted = Dir[File.join(review, "results", "*.json")].to_h { |path| [File.basename(path, ".json"), TimingAudit.sha256_file(path)] }
  missing = ids - accepted.keys
  raise "Unexpected recovery scope" unless accepted.size == 11 && missing.size == 5
  failures = Dir[File.join(review, "logs", "*", "attempt-*", "events.jsonl")].filter_map do |path|
    events = File.readlines(path).map { |line| JSON.parse(line) }
    last = events.last
    next unless last && last["type"] == "turn.failed"
    message = last.dig("error", "message")
    raise "Non-rate-limit reviewer failure" unless message.include?("429 Too Many Requests")
    { "path" => path, "sha256" => TimingAudit.sha256_file(path), "error" => message }
  end
  raise "Missing provider-failure evidence" if failures.empty?
  receipt = {
    "prepared_at" => TimingAudit.utc_now, "not_before" => "2026-10-14T14:40:00Z",
    "model" => "gpt-6.1-sol", "effort" => "xhigh", "jobs" => 2,
    "accepted_result_sha256" => accepted, "missing_ids" => missing,
    "rate_limit_failures" => failures, "previous_progress" => stopped,
    "policy" => "Reuse all valid accepted results and immutable inventories; retry only missing static reviews after cooldown. No generated program, validation, source, prompt, or measurement-policy changes."
  }
  FileUtils.mkdir_p(evidence)
  FileUtils.cp(progress_path, File.join(evidence, "initial-stop.json"))
  FileUtils.cp(File.join(campaign, "audit-full-driver.rb"), File.join(evidence, "audit-full-driver-before-concurrency-reduction.rb"))
  TimingAudit.atomic_write(File.join(evidence, "request.json"), JSON.pretty_generate(receipt) + "\n")
  FileUtils.cp(__FILE__, campaign)
  puts JSON.pretty_generate(receipt.reject { |key, _| key == "rate_limit_failures" || key == "previous_progress" })
elsif mode == "run"
  receipt = JSON.parse(File.read(File.join(evidence, "request.json")))
  raise "Cooldown not elapsed" if Time.now < Time.parse(receipt.fetch("not_before"))
  fingerprint_check = lambda do
    receipt.fetch("accepted_result_sha256").each do |id, sha|
      raise "Accepted review changed: #{id}" unless TimingAudit.sha256_file(File.join(review, "results", "#{id}.json")) == sha
    end
  end
  fingerprint_check.call
  progress = lambda do |phase, extra = {}|
    TimingAudit.atomic_write(File.join(campaign, "audit-pilot-progress.json"), JSON.pretty_generate({
      "updated_at" => TimingAudit.utc_now, "phase" => phase, "pid" => Process.pid,
      "driver_sha256" => TimingAudit.sha256_file(__FILE__), "jobs" => 2,
      "recovery_receipt_sha256" => TimingAudit.sha256_file(File.join(evidence, "request.json"))
    }.merge(extra)) + "\n")
  end
  begin
    progress.call("qtclustering_pilot_sol61_resume")
    QtclusteringBoundary.run_review(main_root: boundary, output_dir: review, scope: "trial", jobs: 2)
    fingerprint_check.call
    progress.call("qtclustering_pilot_gate")
    passed = QtclusteringBoundary.pilot_gate(main_root: boundary, review_root: review)
    raise "QT pilot gate requires investigation" unless passed
    progress.call("awaiting_primary_pilot_quality_review", "qt_gate_passed" => true, "accepted_reviews_unchanged" => 11)
  rescue Exception => error
    progress.call("stopped", "error" => "#{error.class}: #{error.message}")
    raise
  end
else
  raise "Expected prepare or run"
end
