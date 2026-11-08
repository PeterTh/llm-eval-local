# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

campaign = "/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation"
unit = "llm-fable51-medium-correction-revision-20261107.service"
receipt = File.join(campaign, "correction-revision-launch.json")
raise "Revision launch already retained" if File.exist?(receipt)
state, status = Open3.capture2("systemctl", "--user", "show", "llm-fable51-medium-correction-full-20261107.service", "--property=ActiveState", "--value")
raise "Original correction stage still active" unless status.success? && !%w[active activating deactivating].include?(state.strip)
pilot = JSON.parse(File.read(File.join(campaign, "audit-pilot-launch.json")))
raise "Review CLI changed" unless File.realpath("/home/petert/.local/bin/codex") == pilot.fetch("review_cli_path") && Digest::SHA256.file(pilot.fetch("review_cli_path")).hexdigest == pilot.fetch("review_cli_sha256")
names = %w[correction-revision-driver.rb reuse-unchanged-correction-reviews.rb launch-correction-revision.rb]
names.each do |name|
  target = File.join(campaign, name)
  raise "Revision driver already retained" if File.exist?(target)
  FileUtils.cp(File.join(__dir__, name), target)
end
driver = File.join(__dir__, "correction-revision-driver.rb")
log = File.join(campaign, "correction-revision-driver.log")
raise "Revision log already exists" if File.exist?(log)
raise "Revision launch failed" unless system("systemd-run", "--user", "--collect", "--unit=#{unit}",
  "--description=One Fable timing-only scope revision with exact 68-review reuse",
  "--property=WorkingDirectory=#{__dir__}",
  "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", "/usr/bin/ruby", driver)
output, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "InvocationID", "-p", "ExecMainStartTimestamp")
properties = output.lines.to_h { |line| line.strip.split("=", 2) }
raise "Revision did not start" unless status.success? && properties.fetch("ActiveState") == "active"
record = {
  "launched_at" => Time.now.utc.iso8601, "unit" => unit, "properties" => properties,
  "program_id" => "roomsim_claude-fable-5.1-cc-medium_hybrid_r2", "reused_accepted_reviews" => 67,
  "preserved_nonaccepting_reviews_for_targeted_adjudication" => 1,
  "source_only" => true, "program_execution" => false,
  "prior_evidence_preserved" => "Original proposal and both original review roots remain untouched; revision uses separate evidence roots.",
  "drivers" => names.to_h { |name| [name, Digest::SHA256.file(File.join(__dir__, name)).hexdigest] },
  "reuse_template_sha256" => Digest::SHA256.file(File.join(__dir__, "experiment/tools/timing_audit/bin/timing_fix_review_reuse.rb")).hexdigest,
  "reuse_changes" => "Dependency binding and explicit subset selection; an explicit nonaccepting-review subset preserves the raw rejection for fresh targeted adjudication. Literal prompt/source/model/schema/evidence identity checks remain unchanged."
}
File.write(receipt, JSON.pretty_generate(record) + "\n")
puts JSON.pretty_generate(record)
