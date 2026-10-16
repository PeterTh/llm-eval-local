# frozen_string_literal: true

require_relative "experiment/lib/local_evaluation"
require "open3"
stage, unit, driver_name = ARGV
raise "Invalid stage" unless %w[audit-pilot audit-full audit-supplemental correction-pilot correction-full revalidation canary benchmark].include?(stage)
raise "Invalid unit" unless unit&.match?(/\Allm-sonnet55-[a-z0-9-]+\.service\z/)
raise "Invalid driver" unless driver_name&.match?(/\A[a-z0-9-]+\.rb\z/)
campaign = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/evaluation"
output = File.join(campaign, "#{stage}-launch.json")
raise "Launch receipt already exists" if File.exist?(output)
keys = %w[ActiveState SubState ExecMainStatus ExecMainPID InvocationID ExecMainStartTimestamp Environment]
out, status = Open3.capture2("systemctl", "--user", "show", unit, *keys.flat_map { |key| ["-p", key] })
raise "Service inspection failed" unless status.success?
properties = out.lines.to_h { |line| line.strip.split("=", 2) }
raise "Service not active" unless properties.fetch("ActiveState") == "active"
raise "Missing invocation" unless properties.fetch("InvocationID").match?(/\A[0-9a-f]{32}\z/)
driver = File.join(__dir__, driver_name)
report = {
  "recorded_at" => Time.now.utc.iso8601, "stage" => stage, "unit" => unit,
  "properties" => properties, "driver" => driver,
  "driver_sha256" => LocalEvaluation.sha256_file(driver),
  "campaign_sha256" => LocalEvaluation.sha256_file(File.join(campaign, "campaign.json"))
}
if stage.start_with?("audit-", "correction-")
  cli = "/home/petert/.codex/packages/standalone/releases/0.159.0-x86_64-unknown-linux-musl/bin/codex"
  sha = LocalEvaluation.sha256_file(cli)
  raise "Review CLI changed" unless sha == "d2752c52353401f7f6efbfcea68796f4f7a3d3e4769f5d1da53fa49d4856b72f"
  raise "Review CLI absent from service PATH" unless properties.fetch("Environment").include?(File.dirname(cli))
  report["review_cli"] = { "path" => cli, "sha256" => sha, "version" => "0.159.0" }
  report["review_worker_policy"] = "Static source only; shell, web, hooks and integrations disabled. Main workflow alone compiles correction proposals."
end
LocalEvaluation.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report)
