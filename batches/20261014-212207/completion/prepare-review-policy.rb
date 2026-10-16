# frozen_string_literal: true

require_relative "experiment/tools/timing_audit/lib/qtclustering_boundary"
scratch = __dir__
campaign = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/evaluation"
primary = "/home/petert/llm_timing_audit/20261015-sonnet55"
output = File.join(campaign, "review-policy.json")
raise "Policy already exists" if File.exist?(output)
raise "Review method changed" unless TimingAudit.capture!("git", "-C", File.join(scratch, "experiment"), "rev-parse", "HEAD").strip == "1d64276682a115ff62585d445f1e94312f543f5d"
[primary, "#{primary}-qtclustering"].each do |root|
  raise "Pilot gate did not pass: #{root}" unless JSON.parse(File.read(File.join(root, "pilot-review.json"))).fetch("passed")
end
files = Dir[File.join(scratch, "experiment/tools/timing_audit", "{bin,lib,prompts,schemas}", "**", "*")].select { |path| File.file?(path) }.sort
roots = [primary, "#{primary}-qtclustering", "#{primary}-qtclustering-sol61"]
retained = roots.flat_map { |root| Dir[File.join(root, "results", "*.json")] }.sort.to_h { |path| [path, TimingAudit.sha256_file(path)] }
report = {
  "created_at" => TimingAudit.utc_now, "policy" => QtclusteringBoundary::REVIEW_POLICY,
  "authority" => "Established user direction: Luna first; Sol 6.1 only for uncertainty or disagreement, never blanket pilot/defect adjudication.",
  "review_method_commit" => "1d64276682a115ff62585d445f1e94312f543f5d",
  "method_files" => files.to_h { |path| [path, TimingAudit.sha256_file(path)] },
  "retained_results" => retained,
  "qt_pilot_adjudication_plan_sha256" => TimingAudit.sha256_file(File.join(primary + "-qtclustering-sol61", "adjudication-plan-trial.json")),
  "review_workers" => { "luna" => 16, "sol" => 2 },
  "driver_sha256" => TimingAudit.sha256_file(File.join(scratch, "audit-full-driver-policy.rb")),
  "native_validation_and_benchmark_method_changed" => false
}
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report.reject { |key, _| %w[method_files retained_results].include?(key) })
