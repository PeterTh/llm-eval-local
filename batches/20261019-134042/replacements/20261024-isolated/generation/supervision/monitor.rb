# frozen_string_literal: true
require "json"
require "open3"
require "time"
campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
amendment = File.join(campaign, "amendments/20261023-filesystem-isolation")
receipt = JSON.parse(File.read(File.join(amendment, "amendment.json")))
progress = JSON.parse(File.read(File.join(amendment, "progress.json")))
ids = receipt.fetch("affected_observations")
reports = ids.filter_map do |id|
  path = File.join(campaign, "observations", "#{id}.json")
  JSON.parse(File.read(path)) if File.file?(path)
end
done = reports.map { |r| r.fetch("id") }
old = ids.to_h do |id|
  [id, JSON.parse(File.read(File.join(amendment, "superseded-observations", "#{id}.json"))).fetch("raw_total_seconds")]
end
output, status = Open3.capture2("systemctl", "--user", "show", receipt.fetch("generation_unit"),
  "-p", "ActiveState", "-p", "SubState", "-p", "ExecMainStatus")
raise "Cannot inspect service" unless status.success?
unit = output.lines.to_h { |line| line.strip.split("=", 2) }
campaign_progress = JSON.parse(File.read(File.join(campaign, "progress.json")))
active = campaign_progress["active_id"]
active = nil unless ids.include?(active) && !done.include?(active)
now = Time.now.utc
elapsed = active ? [now - Time.parse(campaign_progress.fetch("checked_at")), 0].max : 0
ratio = reports.size >= 3 ? reports.sum { |r| r.fetch("raw_total_seconds") } / done.sum { |id| old.fetch(id) } : 1.0
remaining = [((ids - done).sum { |id| old.fetch(id) } * ratio) - elapsed, 0].max
health = if progress["state"] == "generation_complete"
  "generation_complete"
elsif progress["state"] == "needs_review" || unit["ActiveState"] != "active"
  "needs_review"
elsif campaign_progress["status"] == "quota_wait"
  "quota_wait"
else
  "running"
end
quota_path = File.join(campaign, "quota-latest.json")
quota = File.file?(quota_path) ? JSON.parse(File.read(quota_path)) : nil
report = { "observed_at" => now.iso8601, "health" => health, "unit" => unit,
  "completed" => reports.size, "expected" => 24, "preserved_observations" => 196,
  "active_id" => active, "active_elapsed_seconds" => elapsed.round,
  "outcomes" => reports.group_by { |r| r.fetch("outcome") }.transform_values(&:size),
  "estimated_generation_finish_utc" => health == "running" ? (now + remaining).iso8601 : nil,
  "estimate_basis" => reports.size >= 3 ? "Same affected observations, scaled by replacement/original elapsed ratio" : "Original durations of the same 24 observations; provisional",
  "estimate_replacement_ratio" => ratio.round(3), "excludes" => "Future quota waits and downstream validation/review/benchmarking",
  "quota" => quota, "error" => progress["error"] }
target = File.join(amendment, "monitor-status.json")
File.write(target + ".tmp", JSON.pretty_generate(report) + "\n")
File.rename(target + ".tmp", target)
File.open(File.join(amendment, "monitor-history.jsonl"), "a") { |f| f.puts(JSON.generate(report)) }
puts JSON.generate(report)
if %w[generation_complete needs_review].include?(health)
  system("systemctl", "--user", "stop", "llm-deepseek41-isolated-monitor-20261023.timer")
end
