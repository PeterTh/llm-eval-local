# frozen_string_literal: true
require "json"
require "yaml"
require "digest"
require "fileutils"
require "open3"
require "time"
require_relative "review-request-pacing"

stage = ARGV.fetch(0)
raise "Expected pilot or full" unless ARGV.size == 1 && %w[pilot full].include?(stage)
campaign = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
receipt_path = File.join(campaign, "audit-#{stage}-paced-launch.json")
raise "Paced stage already launched" if File.exist?(receipt_path)
deadline = Time.iso8601("2026-10-30T17:00:00Z")
raise "Fable reset has already occurred" unless Time.now < deadline
%w[pilot full].each do |name|
  %w[normal paced].each do |kind|
    suffix = kind == "paced" ? "-paced" : ""
    unit = "llm-beam10-oc-timing-#{name}#{suffix}-20261030.service"
    state, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
    raise "Cannot inspect review service" unless status.success?
    raise "Review service active" if %w[active activating deactivating].include?(state.strip)
  end
end
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is busy" unless status.exitstatus == 1 && pids.empty?
pilot = JSON.parse(File.read(File.join(campaign, "audit-pilot-launch.json")))
raise "Review CLI changed" unless File.realpath("/home/petert/.local/bin/codex") == pilot.fetch("review_cli_path") && Digest::SHA256.file(pilot.fetch("review_cli_path")).hexdigest == pilot.fetch("review_cli_sha256")
original = File.join(__dir__, stage == "pilot" ? "audit-pilot-driver.rb" : "audit-full-driver-policy.rb")
raise "Retained original driver differs" unless File.binread(original) == File.binread(File.join(campaign, File.basename(original)))
if stage == "pilot"
  progress = JSON.parse(File.read(File.join(campaign, "audit-pilot-progress.json")))
  raise "Unexpected failed pilot phase" unless progress.fetch("phase") == "stopped" && progress.fetch("stopped_phase") == "primary_pilot"
else
  policy = JSON.parse(File.read(File.join(campaign, "review-policy.json")))
  raise "Review policy differs" unless policy.fetch("policy") == "luna_first_uncertainty_or_disagreement_v1" && policy.fetch("driver_sha256") == Digest::SHA256.file(original).hexdigest
  policy.fetch("retained_results").each { |path, sha| raise "Pilot result changed" unless Digest::SHA256.file(path).hexdigest == sha }
  [primary, "#{primary}-qtclustering"].each { |root| raise "Pilot gate failed" unless JSON.parse(File.read(File.join(root, "pilot-review.json"))).fetch("passed") }
  raise "Full stage already launched" if File.exist?(File.join(campaign, "audit-full-launch.json"))
end
roots = [primary, "#{primary}-priority", "#{primary}-sol61", "#{primary}-qtclustering", "#{primary}-qtclustering-sol61"]
retained = roots.flat_map { |root| Dir[File.join(root, "results/*.json")] }.sort.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
format_path = File.join(campaign, "audit-pilot-citation-recovery.json")
format_attempt = File.file?(format_path) ? JSON.parse(File.read(format_path)).fetch("formatting_attempt") : nil
retained_format_failures = []
failures = roots.flat_map { |root| Dir[File.join(root, "logs/*/attempt-*/metadata.yaml")] }.filter_map do |path|
  data = YAML.safe_load_file(path)
  next if data["result_sha256"]
  events_path = File.join(File.dirname(path), "events.jsonl")
  events = File.readlines(events_path).map { |line| JSON.parse(line) }
  unless BeamReviewPacing.pure_rate_limit_failure?(data, events)
    raise "Non-rate-limit failure needs investigation: #{path}" unless format_attempt &&
      path == format_attempt.fetch("metadata_path") && Digest::SHA256.file(path).hexdigest == format_attempt.fetch("metadata_sha256") &&
      Digest::SHA256.file(events_path).hexdigest == format_attempt.fetch("events_sha256")
    retained_format_failures << format_attempt
    next
  end
  { "path" => path, "metadata_sha256" => Digest::SHA256.file(path).hexdigest,
    "events_sha256" => Digest::SHA256.file(events_path).hexdigest, "finished_at" => data.fetch("finished_at") }
end
raise "Pilot recovery scope differs" if stage == "pilot" && (retained.size != 5 || failures.size != 33)
last_failure = failures.map { |record| Time.iso8601(record.fetch("finished_at")) }.max || Time.at(0)
paths = [original, File.join(__dir__, "paced-audit-driver.rb"), File.join(__dir__, "review-request-pacing.rb"),
  File.join(__dir__, "experiment/tools/timing_audit/lib/timing_audit.rb")]
unit = "llm-beam10-oc-timing-#{stage}-paced-20261030.service"
log = File.join(campaign, "audit-#{stage}-paced-driver.log")
raise "Paced log already exists" if File.exist?(log)
report = { "prepared_at" => Time.now.utc.iso8601, "unit" => unit, "stage" => stage,
  "original_driver" => original, "files" => paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
  "retained_results" => retained, "failed_attempts" => failures, "retained_format_failures" => retained_format_failures,
  "launcher_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
  "not_before" => [Time.now, last_failure + 600].max.utc.iso8601, "deadline" => deadline.utc.iso8601,
  "workers" => 1, "minimum_request_spacing_seconds" => 90, "rate_limit_backoff_seconds" => [600, 1200],
  "maximum_consecutive_429_failures_per_program" => 3,
  "review_cli_sha256" => pilot.fetch("review_cli_sha256"), "models_efforts_prompts_and_tool_restrictions_changed" => false,
  "policy" => "Scheduling only around the frozen AuditRunner: retain accepted results; retry only pure pre-output HTTP 429 failures; stop on other failures; preserve the whole review timeout before Fable reset. Luna-first and uncertainty-only Sol selection are unchanged." }
File.write(receipt_path, JSON.pretty_generate(report) + "\n", mode: "wx")
FileUtils.cp(__FILE__, File.join(campaign, "audit-#{stage}-paced-launcher.rb"))
%w[paced-audit-driver.rb review-request-pacing.rb test-review-request-pacing.rb].each do |name|
  original_path, retained_path = File.join(__dir__, name), File.join(campaign, name)
  raise "Retained pacing helper differs: #{name}" if File.file?(retained_path) && File.binread(original_path) != File.binread(retained_path)
  FileUtils.cp(original_path, retained_path) unless File.file?(retained_path)
end
raise "Paced review launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Beam static timing review with bounded provider-rate pacing",
  "--property=WorkingDirectory=#{__dir__}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}",
  "/usr/bin/ruby", File.join(__dir__, "paced-audit-driver.rb"), stage)
output, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "MainPID", "-p", "InvocationID")
raise "Cannot inspect paced service" unless status.success?
properties = output.lines.to_h { |line| line.chomp.split("=", 2) }
raise "Paced service did not start" unless properties.fetch("ActiveState") == "active"
activation = { "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties,
  "pacing_receipt_sha256" => Digest::SHA256.file(receipt_path).hexdigest,
  "driver_sha256" => Digest::SHA256.file(original).hexdigest, "pacing_driver_sha256" => Digest::SHA256.file(File.join(__dir__, "paced-audit-driver.rb")).hexdigest,
  "policy_sha256" => stage == "full" ? Digest::SHA256.file(File.join(campaign, "review-policy.json")).hexdigest : nil,
  "pilot_results_reused" => true, "review_workers_source_only" => true,
  "review_workers_can_compile_or_execute" => false, "review_workers" => { "luna" => 1, "sol" => 1 },
  "stronger_selection" => "Only uncertainty or disagreement; no blanket adjudication" }
File.write(File.join(campaign, "audit-#{stage}-paced-activation.json"), JSON.pretty_generate(activation) + "\n", mode: "wx")
File.write(File.join(campaign, "audit-full-launch.json"), JSON.pretty_generate(activation) + "\n", mode: "wx") if stage == "full"
puts JSON.pretty_generate(activation.merge(report.slice("not_before", "deadline", "minimum_request_spacing_seconds")))
