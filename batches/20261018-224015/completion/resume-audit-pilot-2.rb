require "json"
require "digest"
require "open3"
require "fileutils"
require "time"

root = "/home/petert/llm_para_campaigns/20261018-224015-luna6-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261019-luna6-opencode"
boundary = "#{primary}-qtclustering"
receipt = File.join(root, "audit-pilot-resume-2.json")
raise "Resume already recorded" if File.exist?(receipt)
previous = JSON.parse(File.read(File.join(root, "audit-pilot-progress.json")))
raise "Unexpected stopped phase" unless previous.fetch("phase") == "stopped" && previous.fetch("stopped_phase") == "qtclustering_pilot"
pending = [primary, boundary].flat_map do |path|
  File.readlines(File.join(path, "trial-ids.txt"), chomp: true).reject { |id| File.exist?(File.join(path, "results", "#{id}.json")) }
end
raise "Unexpected missing reviews" unless pending == ["qtclustering_gpt-6-luna-oc-medium_omp_r5"]
capacity = Dir[File.join(boundary, "logs", pending.first, "attempt-*", "events.jsonl")].sort
raise "Failure is not the inspected capacity issue" unless capacity.size == 6 && capacity.all? do |path|
  File.foreach(path).any? { |line| JSON.parse(line).dig("error", "message") == "Selected model is at capacity. Please try a different model." }
end
pilot = JSON.parse(File.read(File.join(root, "audit-pilot-launch.json")))
raise "Review CLI changed" unless File.realpath("/home/petert/.local/bin/codex") == pilot.fetch("review_cli_path") &&
  Digest::SHA256.file(pilot.fetch("review_cli_path")).hexdigest == pilot.fetch("review_cli_sha256")
[pilot.fetch("unit"), "llm-luna6-oc-timing-pilot-resume-1-20261019.service"].each do |previous_unit|
  state, status = Open3.capture2("systemctl", "--user", "show", previous_unit, "-p", "ActiveState", "--value")
  raise "Previous pilot is still active" unless status.success? && !%w[active activating reloading].include?(state.strip)
end
driver = File.join(__dir__, "audit-pilot-driver.rb")
raise "Review driver changed" unless Digest::SHA256.file(driver).hexdigest == pilot.fetch("driver_sha256")
retained = [primary, boundary].flat_map { |path| Dir[File.join(path, "results/*.json")] }.sort.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
raise "Unexpected retained reviews" unless retained.size == 27
unit = "llm-luna6-oc-timing-pilot-resume-2-20261019.service"
log = File.join(root, "audit-pilot-driver.log")
raise "Resume launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=Luna OpenCode timing pilot: retry one missing capacity-limited review",
  "--property=WorkingDirectory=#{__dir__}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", "/usr/bin/ruby", driver)
report = {
  "launched_at" => Time.now.utc.iso8601, "unit" => unit, "previous_progress" => previous,
  "reason" => "One source-only review exhausted bounded attempts during transient provider model-capacity errors; no scientific or model-policy change.",
  "pending_primary_reviews" => pending, "retained_results_sha256" => retained,
  "failed_attempt_sha256" => capacity.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
  "driver_sha256" => Digest::SHA256.file(driver).hexdigest,
  "resume_policy" => "Existing verified reviews are skipped; new attempts append without overwriting prior evidence. Then continue the original uncertainty-only QT adjudication and pilot gate."
}
File.write(receipt, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, root)
puts JSON.pretty_generate(report.except("retained_results_sha256", "failed_attempt_sha256"))
