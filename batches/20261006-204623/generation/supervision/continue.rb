require "json"
require "open3"
require "time"
$stdout.sync = true
$stderr.sync = true
root = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(root, "campaign.json")))
puts "Waiting for the two reusable production preflights at #{Time.now.utc.iso8601}"
loop do
  output, status = Open3.capture2("systemctl", "--user", "show", manifest.fetch("preflight_unit"),
    "-p", "ActiveState", "-p", "Result", "-p", "ExecMainStatus")
  raise "Cannot inspect the preflight service" unless status.success?
  state = output.lines.to_h { |line| line.strip.split("=", 2) }
  if %w[active activating deactivating].include?(state["ActiveState"])
    sleep 15
    next
  end
  unless state["ActiveState"] == "inactive" && state["Result"] == "success" && state["ExecMainStatus"] == "0"
    raise "Preflight service did not succeed: #{state.inspect}; inspect preflight.log and progress.json"
  end
  gate = JSON.parse(File.read(File.join(root, "preflight-gate.json")))
  progress = JSON.parse(File.read(File.join(root, "progress.json")))
  unless gate.fetch("accepted") && progress.fetch("status") == "preflight_complete"
    raise "Preflight acceptance is incomplete"
  end
  break
end
puts "Preflight accepted; continuing the frozen campaign at #{Time.now.utc.iso8601}"
exec "/usr/bin/ruby", File.join(manifest.fetch("working_directory"), "tools/generation_campaign.rb"), "run", root
