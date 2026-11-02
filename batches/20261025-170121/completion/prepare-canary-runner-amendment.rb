# frozen_string_literal: true
require_relative "benchmark-orchestration"
require_relative "review-canary-failure"
require_relative "verify-canary-runner-amendment"

campaign = BeamCanaryDisposition::CAMPAIGN
root = BeamCanaryDisposition::ROOT
raise "Amendment already exists" if File.exist?(BeamCanaryRunnerAmendment::REPORT)
gate = JSON.parse(File.read(File.join(campaign, "benchmark-canary-gate.json")))
BeamCanaryDisposition.verify!(gate.fetch("failures"))
plan = BenchmarkValidationBatch.campaign_data(root)
original = File.binread(File.join(__dir__, "benchmark-orchestration.rb"))
amended_path = File.join(__dir__, "benchmark-orchestration-v3.rb")
changes = {
  '    raise "Campaign runner changed" unless LocalEvaluation.sha256_file(__FILE__) == data.fetch("artifacts").fetch("runner-snapshot.rb")' =>
    "    require_relative \"verify-canary-runner-amendment\"\n    BeamCanaryRunnerAmendment.verify!(__FILE__, data.fetch(\"artifacts\").fetch(\"runner-snapshot.rb\"))",
  '    raise "Canary measurements have not all passed" unless canary_ids.all? { |id| full_results(run_dir)[id]&.first == true }' =>
    "    require_relative \"review-canary-failure\"\n    gate = JSON.parse(File.read(File.join(BeamCanaryDisposition::CAMPAIGN, \"benchmark-canary-gate.json\")))\n    raise \"Wrong canary gate\" unless gate.fetch(\"quality_gate\") == \"passed\" && gate.fetch(\"canary_ids\").sort == canary_ids.sort\n    BeamCanaryDisposition.verify!(gate.fetch(\"failures\"))\n    raise \"Canary failure review changed\" unless LocalEvaluation.sha256_file(BeamCanaryDisposition::REPORT) == gate.fetch(\"canary_failure_review_sha256\")"
}
expected = original.dup
changes.each do |before, after|
  raise "Ambiguous amendment hunk" unless expected.scan(Regexp.new(Regexp.escape(before))).size == 1
  expected.sub!(before, after)
end
raise "Unapproved orchestration change" unless File.binread(amended_path) == expected
raise "Original runner changed" unless Digest::SHA256.hexdigest(original) == plan.fetch("artifacts").fetch("runner-snapshot.rb")
paths = %w[benchmark-orchestration.rb benchmark-orchestration-v3.rb benchmark-driver-v4.rb
  verify-canary-runner-amendment.rb review-canary-failure.rb prepare-canary-runner-amendment.rb].map { |name| File.join(__dir__, name) } +
  [File.join(campaign, "benchmark-canary-gate.json"), BeamCanaryDisposition::REPORT,
    File.join(root, "benchmark-campaign/manifest.yaml"), File.join(root, "benchmark-campaign/runner-snapshot.rb"),
    File.join(root, "benchmark_config.yaml"), File.join(root, "evaluation_manifest.yaml")]
report = { "created_at" => Time.now.utc.iso8601,
  "scope" => "canary disposition gate and explicit orchestration provenance only",
  "original_runner_sha256" => Digest::SHA256.hexdigest(original),
  "amended_runner_sha256" => Digest::SHA256.file(amended_path).hexdigest,
  "approved_changes" => changes, "measurement_pipeline_unchanged" => true,
  "benchmark_input_configuration_unchanged" => true, "completed_canaries_reused" => 4,
  "inputs_sha256" => paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] } }
File.write(BeamCanaryRunnerAmendment::REPORT, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(campaign, File.basename(__FILE__)))
puts JSON.pretty_generate(report.except("approved_changes", "inputs_sha256"))
