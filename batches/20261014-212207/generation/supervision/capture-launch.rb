require "json"
require "time"
require "digest"
require "open3"
require "fileutils"

root = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
raise "Launch receipt already exists" if File.exist?(File.join(root, "launch.json"))
units = %w[preflight_unit generation_unit monitor_unit monitor_timer].map { |key| manifest.fetch(key) }
records = units.to_h do |unit|
  output, status = Open3.capture2("systemctl", "--user", "show", unit,
    "-p", "Id", "-p", "InvocationID", "-p", "ActiveState", "-p", "SubState", "-p", "ExecStart",
    "-p", "WorkingDirectory", "-p", "StandardOutput", "-p", "StandardError", "-p", "KillMode",
    "-p", "TimersMonotonic", "-p", "NextElapseUSecMonotonic")
  raise "Cannot inspect #{unit}" unless status.success?
  [unit, output.lines.to_h { |line| line.strip.split("=", 2) }]
end
raise "Generation is not active" unless records.fetch(manifest.fetch("generation_unit")).fetch("ActiveState") == "active"
raise "Monitoring timer is not active" unless records.fetch(manifest.fetch("monitor_timer")).fetch("ActiveState") == "active"
review = File.join(root, "preflight-review.json")
raise "Preflight review is not accepted" unless JSON.parse(File.read(review)).fetch("accepted")
receipt = { "recorded_at" => Time.now.utc.iso8601, "campaign_id" => manifest.fetch("campaign_id"),
  "units" => records, "preflight_review_sha256" => Digest::SHA256.file(review).hexdigest,
  "launch_files" => %w[prepare.rb inspect_claude.rb run.rb monitor.rb verify-preflight.rb capture-launch.rb].to_h { |name| [name, Digest::SHA256.file(File.join(__dir__, name)).hexdigest] },
  "monitoring" => "Four-hour lightweight status timer; it records and stops on terminal state, without automatic generation retries or chat wakeup." }
File.write(File.join(root, "launch.json"), JSON.pretty_generate(receipt) + "\n")
FileUtils.cp(__FILE__, File.join(root, "capture-launch.rb"))
puts JSON.pretty_generate(receipt)
