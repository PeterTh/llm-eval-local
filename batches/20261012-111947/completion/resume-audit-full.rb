# frozen_string_literal: true

$stdout.sync = true
require "/tmp/haiku55-evaluation-20261014.ZqhO2v/review-method/tools/timing_audit/bin/timing_finalize_audit"
require "/tmp/haiku55-evaluation-20261014.ZqhO2v/review-method/tools/timing_audit/lib/qtclustering_boundary"

campaign = "/home/petert/llm_para_campaigns/20261012-111947-haiku55-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261014-haiku55"
review = "#{primary}-sol61"
boundary = "#{primary}-qtclustering"
evidence = File.join(campaign, "full-review-provider-recovery")
progress_path = File.join(campaign, "audit-full-progress.json")
mode = ARGV.fetch(0)

if mode == "prepare"
  raise "Recovery already prepared" if File.exist?(evidence)
  stopped = JSON.parse(File.read(progress_path))
  raise "Unexpected stop" unless stopped["phase"] == "stopped" && stopped["stopped_phase"] == "sol61_adjudication"
  raise "Main audit already finalized" if File.exist?(File.join(primary, "final"))
  selected = TimingAudit.load_jsonl(File.join(review, "inventory.jsonl")).map { |row| row.fetch("id") }
  accepted = Dir[File.join(review, "results/*.json")].to_h do |path|
    result = JSON.parse(File.read(path))
    id = result.fetch("program_id")
    TimingAudit::AuditVerifier.new(review, "full").verify_result!(id, result)
    [id, TimingAudit.sha256_file(path)]
  end
  missing = selected - accepted.keys
  raise "No missing reviews" if missing.empty?
  failures = missing.map do |id|
    metadata_path = Dir[File.join(review, "logs", id, "attempt-*/metadata.yaml")].max_by do |path|
      YAML.safe_load_file(path).fetch("attempt")
    end
    raise "Missing failed-attempt metadata for #{id}" unless metadata_path
    metadata = YAML.safe_load_file(metadata_path)
    events_path = File.join(File.dirname(metadata_path), "events.jsonl")
    final = TimingAudit.load_jsonl(events_path).last
    raise "Not a provider-only 429 failure for #{id}" unless metadata.fetch("exit_code") != 0 &&
      !metadata.fetch("timed_out") && final&.fetch("type") == "turn.failed" &&
      final.dig("error", "message").to_s.include?("429 Too Many Requests")
    { "id" => id, "metadata_path" => metadata_path,
      "metadata_sha256" => TimingAudit.sha256_file(metadata_path),
      "events_path" => events_path, "events_sha256" => TimingAudit.sha256_file(events_path),
      "finished_at" => metadata.fetch("finished_at"), "error" => final.fetch("error") }
  end
  not_before = failures.map { |row| Time.parse(row.fetch("finished_at")) + 600 }.max
  receipt = {
    "prepared_at" => TimingAudit.utc_now, "not_before" => not_before.utc.iso8601,
    "model" => "gpt-6.1-sol", "effort" => "xhigh", "jobs" => 1,
    "accepted_result_sha256" => accepted, "missing_ids" => missing,
    "provider_failures" => failures, "previous_progress" => stopped,
    "inventory_sha256" => TimingAudit.sha256_file(File.join(review, "inventory.jsonl")),
    "review_policy_receipt_sha256" => TimingAudit.sha256_file(File.join(campaign, "review-policy-continuation.json")),
    "driver_sha256" => TimingAudit.sha256_file(__FILE__),
    "policy" => "Reuse completed reviews unchanged; retry only missing HTTP 429 failures after at least ten minutes. No program execution, validation replay, source or scientific-policy changes."
  }
  FileUtils.mkdir_p(evidence)
  FileUtils.cp(progress_path, File.join(evidence, "initial-stop.json"))
  FileUtils.cp(File.join(campaign, "audit-full-driver-policy.log"), File.join(evidence, "initial-driver.log"))
  FileUtils.cp(__FILE__, campaign)
  TimingAudit.atomic_write(File.join(evidence, "request.json"), JSON.pretty_generate(receipt) + "\n")
  puts JSON.pretty_generate(receipt.reject { |key, _| %w[accepted_result_sha256 provider_failures previous_progress].include?(key) })
elsif mode == "run"
  receipt = JSON.parse(File.read(File.join(evidence, "request.json")))
  raise "Cooldown not elapsed" if Time.now < Time.parse(receipt.fetch("not_before"))
  raise "Recovery driver changed" unless receipt.fetch("driver_sha256") == TimingAudit.sha256_file(__FILE__)
  raise "Inventory changed" unless receipt.fetch("inventory_sha256") == TimingAudit.sha256_file(File.join(review, "inventory.jsonl"))
  policy_path = File.join(campaign, "review-policy-continuation.json")
  raise "Review policy changed" unless receipt.fetch("review_policy_receipt_sha256") == TimingAudit.sha256_file(policy_path)
  policy = JSON.parse(File.read(policy_path))
  policy.fetch("retained_results").merge(policy.fetch("method_files")).each do |path, digest|
    raise "Pinned review evidence or method changed: #{path}" unless TimingAudit.sha256_file(path) == digest
  end
  verify_retained = lambda do
    receipt.fetch("accepted_result_sha256").each do |id, digest|
      raise "Completed review changed: #{id}" unless TimingAudit.sha256_file(File.join(review, "results", "#{id}.json")) == digest
    end
  end
  phase = "sol61_provider_retry"
  checkpoint = lambda do |extra = {}|
    TimingAudit.atomic_write(progress_path, JSON.pretty_generate({
      "updated_at" => TimingAudit.utc_now, "pid" => Process.pid, "phase" => phase,
      "driver_sha256" => TimingAudit.sha256_file(__FILE__),
      "recovery_receipt_sha256" => TimingAudit.sha256_file(File.join(evidence, "request.json"))
    }.merge(extra)) + "\n")
  end
  begin
    verify_retained.call
    checkpoint.call
    missing = receipt.fetch("missing_ids")
    raise "Empty retry scope" if missing.empty?
    TimingAudit::AuditRunner.new(output_dir: review, scope: "full", jobs: 1,
      model: "gpt-6.1-sol", effort: "xhigh", only_ids: missing).run
    verify_retained.call
    TimingAudit::AuditVerifier.new(review, "full").run
    phase = "finalize_mpi_hybrid"
    checkpoint.call
    TimingFinalizeAudit.run(main_root: primary, priority_root: "#{primary}-priority", adjudication_root: review)
    phase = "qtclustering_full"
    checkpoint.call
    TimingAudit::AuditRunner.new(output_dir: boundary, scope: "full", jobs: 16,
      model: "gpt-5.6-luna", effort: "high").run
    phase = "qtclustering_uncertainty_only_sol61"
    checkpoint.call
    QtclusteringBoundary.run_review(main_root: boundary, output_dir: "#{boundary}-sol61", scope: "full", jobs: 2)
    phase = "finalize_qtclustering"
    checkpoint.call
    QtclusteringBoundary.finalize(main_root: boundary, review_root: "#{boundary}-sol61") unless File.directory?(File.join(boundary, "final"))
    verify_retained.call
    phase = "awaiting_correction_review"
    checkpoint.call("retained_adjudications_unchanged" => receipt.fetch("accepted_result_sha256").size)
  rescue Exception => error
    stopped_phase = phase
    phase = "stopped"
    checkpoint.call("stopped_phase" => stopped_phase, "error" => "#{error.class}: #{error.message}")
    raise
  end
else
  raise "Expected prepare or run"
end
