# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

mode = ARGV.fetch(0)
raise "Use check or launch" unless ARGV.size == 1 && %w[check launch].include?(mode)
evaluation = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
fable = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium"
checkpoint_path = File.join(evaluation, "audit-fable-yield-20261030.json")
raise "Yield checkpoint changed" unless Digest::SHA256.file(checkpoint_path).hexdigest == "24da84c5ceb0f79007b4ce865aabdddb6dba01bf36119a560d8893b474e7abf4"
checkpoint = JSON.parse(File.read(checkpoint_path))
checkpoint.fetch("input_sha256").each { |name, sha| raise "Review input changed: #{name}" unless Digest::SHA256.file(File.join(evaluation, name)).hexdigest == sha }
retained = {}
counts = {}
checkpoint.fetch("review_roots").each do |root, row|
  raise "Review root existence differs" unless File.directory?(root) == row.fetch("exists")
  row.fetch("manifest_sha256").each { |name, sha| raise "Review manifest changed: #{name}" unless Digest::SHA256.file(File.join(root, name)).hexdigest == sha }
  actual = Dir[File.join(root, "results/*.json")].sort
  raise "Review result scope changed: #{root}" unless actual == row.fetch("result_sha256").keys.sort
  row.fetch("result_sha256").each { |path, sha| raise "Accepted review changed: #{path}" unless Digest::SHA256.file(path).hexdigest == sha }
  retained.merge!(row.fetch("result_sha256"))
  counts[root] = actual.size
end
raise "Wrong retained scope" unless retained.size == 114
old_launch_path = File.join(evaluation, "audit-full-paced-launch.json")
old_launch = JSON.parse(File.read(old_launch_path))
old_launch.fetch("files").each { |path, sha| raise "Frozen method changed: #{path}" unless Digest::SHA256.file(path).hexdigest == sha }
old_launch.fetch("failed_attempts").each do |row|
  raise "Failed attempt metadata changed" unless Digest::SHA256.file(row.fetch("path")).hexdigest == row.fetch("metadata_sha256")
  raise "Failed attempt stream changed" unless Digest::SHA256.file(File.join(File.dirname(row.fetch("path")), "events.jsonl")).hexdigest == row.fetch("events_sha256")
end
old_launch.fetch("retained_format_failures").each do |row|
  raise "Formatting failure metadata changed" unless Digest::SHA256.file(row.fetch("metadata_path")).hexdigest == row.fetch("metadata_sha256")
  events = File.join(File.dirname(row.fetch("metadata_path")), "events.jsonl")
  raise "Formatting failure stream changed" unless Digest::SHA256.file(events).hexdigest == row.fetch("events_sha256")
end
pilot = JSON.parse(File.read(File.join(evaluation, "audit-pilot-launch.json")))
cli = pilot.fetch("review_cli_path")
raise "Pinned review CLI changed" unless Digest::SHA256.file(cli).hexdigest == pilot.fetch("review_cli_sha256")
version, status = Open3.capture2e(cli, "--version")
raise "Pinned CLI unavailable" unless status.success? && version.strip == "codex-cli 0.159.0"
fable_receipt_path = File.join(fable, "quota-resume-20261030/tranche-completion-20261031.json")
raise "Fable pause receipt changed" unless Digest::SHA256.file(fable_receipt_path).hexdigest == "0286d9db8910396fdc86e141fc566b54768148d6924780cc3dd235128e87f6cc"
fable_receipt = JSON.parse(File.read(fable_receipt_path))
raise "Fable pause differs" unless fable_receipt.values_at("status", "completed", "evaluation_account_idle") == ["quota_paused_account_idle", 194, true]
fable_progress = JSON.parse(File.read(File.join(fable, "progress.json")))
raise "Fable is no longer paused" unless fable_progress.values_at("status", "completed", "active_id") == ["quota_paused", 194, nil] && File.file?(File.join(fable, "STOP"))
units = fable_receipt.fetch("units").keys + ["llm-beam10-oc-timing-full-paced-20261030.service", "llm-beam10-oc-timing-full-resume-20261031.service"]
units.each do |unit|
  output, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "--value")
  raise "Campaign/review unit active: #{unit}" unless status.success? && output.strip == "inactive"
end
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account is busy" unless status.exitstatus == 1 && pids.empty?
deadline = Time.iso8601(fable_receipt.fetch("next_weekly_reset"))
raise "Next Fable reset is too near" unless Time.now + 930 < deadline
raise "Corrections already started" if File.file?(File.join(evaluation, "correction-commit.json"))
receipt_path = File.join(evaluation, "audit-full-resume-20261031-launch.json")
log = File.join(evaluation, "audit-full-resume-20261031-driver.log")
raise "Resume already launched" if File.exist?(receipt_path) || File.exist?(log)
summary = { "checked_at" => Time.now.utc.iso8601, "retained_review_counts" => counts,
  "retained_review_count" => retained.size, "review_cli" => cli, "review_cli_version" => version.strip,
  "workers" => 1, "minimum_request_spacing_seconds" => 90, "deadline" => deadline.utc.iso8601,
  "source_only" => true, "stronger_selection" => "Only uncertainty or disagreement; no blanket Sol adjudication" }
if mode == "check"
  puts JSON.pretty_generate(summary.merge("preflight_passed" => true, "model_requests" => 0))
  exit
end
wrapper = File.join(__dir__, "paced-audit-resume-20261031.rb")
files = old_launch.fetch("files").merge(wrapper => Digest::SHA256.file(wrapper).hexdigest)
unit = "llm-beam10-oc-timing-full-resume-20261031.service"
path_env = "#{File.dirname(cli)}:/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin"
record = summary.merge("unit" => unit, "original_driver" => old_launch.fetch("original_driver"),
  "files" => files, "retained_results" => retained, "not_before" => Time.now.utc.iso8601,
  "yield_checkpoint_sha256" => Digest::SHA256.file(checkpoint_path).hexdigest,
  "fable_tranche_receipt_sha256" => Digest::SHA256.file(fable_receipt_path).hexdigest,
  "old_launch_sha256" => Digest::SHA256.file(old_launch_path).hexdigest,
  "review_cli_sha256" => pilot.fetch("review_cli_sha256"), "path" => path_env,
  "launcher_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
  "rate_limit_backoff_seconds" => [600, 1200], "maximum_consecutive_429_failures_per_program" => 3,
  "models_efforts_prompts_and_tool_restrictions_changed" => false,
  "policy" => "Resume only missing reviews after the safe Fable yield, retaining all accepted reviews and raw attempts. The frozen runner, Luna-first policy and one-worker pacing are unchanged. No generation, validation or benchmarks are repeated.")
File.write(receipt_path, JSON.pretty_generate(record) + "\n", mode: "wx")
[__FILE__, wrapper].each { |path| FileUtils.copy_file(path, File.join(evaluation, File.basename(path))) }
raise "Review resume launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Resume Beam source-only timing review after Fable weekly pause",
  "--property=WorkingDirectory=#{__dir__}", "--setenv=PATH=#{path_env}",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", "/usr/bin/ruby", wrapper)
output, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "MainPID", "-p", "InvocationID")
raise "Cannot inspect resumed review" unless status.success?
properties = output.lines.to_h { |line| line.chomp.split("=", 2) }
raise "Resumed review did not start" unless properties.fetch("ActiveState") == "active"
activation = { "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties,
  "launch_receipt_sha256" => Digest::SHA256.file(receipt_path).hexdigest, "retained_review_count" => retained.size }
File.write(File.join(evaluation, "audit-full-resume-20261031-activation.json"), JSON.pretty_generate(activation) + "\n", mode: "wx")
puts JSON.pretty_generate(activation)
