# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

evaluation = "/home/petert/llm_para_campaigns/20261025-170121-beam10-opencode-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261030-beam10-opencode"
unit = "llm-beam10-oc-timing-full-paced-20261030.service"
output, status = Open3.capture2("systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "MainPID", "-p", "ExecMainStatus")
raise "Cannot inspect review service" unless status.success?
service = output.lines.to_h { |line| line.chomp.split("=", 2) }
raise "Review has not exited cleanly" unless service.values_at("ActiveState", "MainPID", "ExecMainStatus") == ["inactive", "0", "0"]
paced_path = File.join(evaluation, "audit-full-paced-progress.json")
stage_path = File.join(evaluation, "audit-full-progress.json")
paced = JSON.parse(File.read(paced_path))
stage = JSON.parse(File.read(stage_path))
raise "Unexpected review stop" unless paced.fetch("phase") == "yielded_for_fable_reset" &&
  paced.fetch("deadline") == "2026-10-30T17:00:00Z" && stage.fetch("stopped_phase") == "independent_review" &&
  stage.fetch("error").start_with?("BeamReviewPacing::YieldForFable:")
raise "Correction work unexpectedly exists" if File.file?(File.join(evaluation, "correction-commit.json"))
roots = [primary, "#{primary}-priority", "#{primary}-sol61", "#{primary}-qtclustering", "#{primary}-qtclustering-sol61"]
records = roots.to_h do |root|
  results = Dir[File.join(root, "results/*.json")].sort
  manifests = %w[manifest.yaml inventory.jsonl trial-ids.txt result-schema.json pilot-review.json].filter_map do |name|
    path = File.join(root, name)
    [name, Digest::SHA256.file(path).hexdigest] if File.file?(path)
  end.to_h
  [root, { "exists" => File.directory?(root), "completed" => results.size,
    "manifest_sha256" => manifests,
    "result_sha256" => results.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] } }]
end
raise "Completed review scope differs" unless records.fetch(primary).fetch("completed") == 80 &&
  records.fetch("#{primary}-priority").fetch("completed") == 21 &&
  records.fetch("#{primary}-qtclustering").fetch("completed") == 13
inputs = %w[audit-full-paced-launch.json audit-full-paced-activation.json review-policy.json validation-completion-review.json]
receipt = {
  "retained_at" => Time.now.utc.iso8601, "unit" => unit, "service" => service,
  "pacing_progress" => paced, "stage_progress" => stage, "review_roots" => records,
  "input_sha256" => inputs.to_h { |name| [name, Digest::SHA256.file(File.join(evaluation, name)).hexdigest] },
  "source_commit" => "74652eee82e2473660a7e75f3ad5d77fd0e3759c",
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest,
  "policy" => "Scheduled safe yield before Fable quota reset, not a review failure. Preserve all accepted reviews and raw attempts. Resume only missing reviews with the same frozen method and pacing under a new launch receipt after Fable releases the host. No generated program, native validation or benchmark is rerun."
}
path = File.join(evaluation, "audit-fable-yield-20261030.json")
File.write(path, JSON.pretty_generate(receipt) + "\n", mode: "wx")
FileUtils.cp(__FILE__, evaluation)
puts JSON.pretty_generate({ "path" => path, "sha256" => Digest::SHA256.file(path).hexdigest,
  "completed_reviews" => records.transform_values { |row| row.fetch("completed") }, "service" => service })
