# frozen_string_literal: true
require "json"
require "open3"
require "fileutils"
require "digest"
require "time"

scratch = __dir__
campaign = "/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation"
validation = "/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v4"
unit = "llm-gpt62-medium-timing-pilot-20261125.service"
receipt = File.join(campaign, "audit-pilot-launch.json")
raise "Pilot already launched" if File.exist?(receipt)
completion = JSON.parse(File.read(File.join(validation, "validation-completion-review.json")))
raise "Validation incomplete" unless completion.fetch("completed") == 440 && completion.fetch("infrastructure_errors").empty?
raise "Validation results changed" unless Digest::SHA256.file(File.join(validation, "validation/all_validation_results.yaml")).hexdigest == completion.fetch("validation_results_sha256")
state, = Open3.capture2("systemctl", "--user", "show", "llm-gpt62-medium-validation-20261125.service", "--property=ActiveState", "--value")
raise "Validation still active" if %w[active activating reloading].include?(state.strip)
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Evaluation account not idle" unless status.exitstatus == 1 && pids.empty?
log = File.join(campaign, "audit-pilot-driver.log")
raise "Pilot log already exists" if File.exist?(log)
%w[adapt-review-templates.rb audit-pilot-driver.rb audit-full-driver-policy.rb verify-primary-pilot.rb verify-audit-completion.rb prepare-review-policy.rb launch-audit-pilot.rb timing-platform-context.txt].each do |name|
  FileUtils.cp(File.join(scratch, name), File.join(campaign, name))
end
FileUtils.cp(File.join(scratch, "timing-platform-context.txt"), File.join(validation, "timing-platform-context.txt"))
version, status = Open3.capture2e("/home/petert/.local/bin/codex", "--version")
raise "Review CLI unavailable" unless status.success?
command = ["systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Astra 6.2 and Sol 6.2 Medium source-only timing audit pilot",
  "--property=WorkingDirectory=#{scratch}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}",
  "/usr/bin/ruby", File.join(scratch, "audit-pilot-driver.rb")]
raise "Pilot launch failed" unless system(*command)
out, status = Open3.capture2("systemctl", "--user", "show", unit,
  "-p", "ActiveState", "-p", "SubState", "-p", "InvocationID", "-p", "ExecMainStartTimestamp")
raise "Pilot service inspection failed" unless status.success?
properties = out.lines.to_h { |line| line.strip.split("=", 2) }
raise "Pilot did not start" unless properties.fetch("ActiveState") == "active"
report = {
  "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties,
  "validation_report_sha256" => Digest::SHA256.file(File.join(validation, "validation-completion-review.json")).hexdigest,
  "driver_sha256" => Digest::SHA256.file(File.join(scratch, "audit-pilot-driver.rb")).hexdigest,
  "context_sha256" => Digest::SHA256.file(File.join(validation, "timing-platform-context.txt")).hexdigest,
  "review_cli_version" => version.strip,
  "review_cli_path" => File.realpath("/home/petert/.local/bin/codex"),
  "review_cli_sha256" => Digest::SHA256.file(File.realpath("/home/petert/.local/bin/codex")).hexdigest,
  "primary_workers" => 4, "primary_model" => "gpt-5.6-luna", "primary_effort" => "high",
  "stronger_model" => "gpt-6.1-sol", "stronger_effort" => "xhigh", "stronger_workers" => 2,
  "stronger_selection" => "Only uncertainty or disagreement; no blanket adjudication",
  "review_workers_source_only" => true, "review_workers_can_compile_or_execute" => false,
  "passing_mpi_hybrid" => completion.fetch("passing_mpi_hybrid"),
  "passing_qtclustering" => completion.fetch("passing_qtclustering")
}
File.write(receipt, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
