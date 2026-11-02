# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "time"
require_relative "verified-external-validation"

scratch = __dir__
campaign = BeamExternalValidation::CAMPAIGN
method = File.join(scratch, "experiment-benchmark/tools/timing_audit")
native = File.join(scratch, "experiment")
BeamExternalValidation.verify!
specifications = {
  "validation-export.rb" => [File.join(method, "bin/export_validation_audit.rb"), {
    'require_relative "../lib/timing_audit"' => "require #{File.join(native, 'tools/timing_audit/lib/timing_audit').inspect}",
    'require_relative "../../../lib/local_evaluation"' => "require #{File.join(native, 'lib/local_evaluation').inspect}",
    '__dir__' => File.join(method, "bin").inspect
  }],
  "correction-export.rb" => [File.join(method, "bin/export_timing_corrections.rb"), {
    'require_relative "../lib/timing_fix_adjudication"' => "require #{File.join(method, 'lib/timing_fix_adjudication').inspect}",
    'require_relative "export_validation_audit"' => 'require_relative "validation-export"',
    'File.expand_path("..", __dir__)' => method.inspect
  }],
  "benchmark-export-v2.rb" => [File.join(method, "bin/export_benchmark_batch.rb"), {
    'require_relative "benchmark_validation_batch"' => 'require_relative "benchmark-orchestration"',
    'require_relative "export_timing_corrections"' => 'require_relative "correction-export"'
  }],
  "export-completed-batch-v2.rb" => [File.join(scratch, "export-completed-batch.rb"), {
    'require_relative "experiment/tools/timing_audit/bin/export_validation_audit"' => 'require_relative "validation-export"',
    'require_relative "benchmark-export"' => 'require_relative "benchmark-export-v2"',
    'report.fetch("completed") == 180' => 'report.fetch("completed") == 179',
    'scratch = __dir__' => "require_relative \"verify-revalidation-boundary\"\nBeamRevalidationBoundary.verify!\nscratch = __dir__",
    'BenchmarkBatchExport.run(run_dir: native, batch_dir: batch,' => <<~'INSERT'.strip
      supplemental_source = File.join(BeamRevalidationBoundary::ROOT, "external-validation")
      supplemental_destination = File.join(batch, "timing-corrections/revalidation/external-validation")
      FileUtils.mkdir_p(supplemental_destination)
      Dir[File.join(supplemental_source, "**/*")].sort.each do |file|
        next unless File.file?(file)
        raise "Unexpected supplemental artifact" unless File.basename(file) == "result.json" || File.basename(file).match?(/\Avalidation_out_(command|stdout|stderr|exitcode|wall_time)\.log\z/)
        destination = File.join(supplemental_destination, file.delete_prefix(supplemental_source + "/"))
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(file, destination)
      end
      FileUtils.cp(BeamRevalidationBoundary::REPORT, File.join(supplemental_destination, "completion.json"))
      BenchmarkBatchExport.run(run_dir: native, batch_dir: batch,
    INSERT
  }]
}
records = specifications.map do |name, (source, substitutions)|
  destination = File.join(scratch, name)
  bytes = File.read(source)
  substitutions.each do |before, after|
    raise "Exporter substitution missing: #{before}" unless bytes.include?(before)
    bytes = bytes.gsub(before, after)
  end
  raise "Prepared export binding differs: #{name}" if File.exist?(destination) && File.binread(destination) != bytes
  File.write(destination, bytes) unless File.exist?(destination)
  raise "Invalid exporter syntax" unless system("ruby", "-c", destination)
  FileUtils.cp(destination, File.join(campaign, name))
  { "template" => source, "template_sha256" => Digest::SHA256.file(source).hexdigest,
    "output" => destination, "sha256" => Digest::SHA256.hexdigest(bytes), "substitutions" => substitutions }
end
report = { "prepared_at" => Time.now.utc.iso8601, "bindings" => records,
  "policy" => "New exclusion-aware exports and source-only timing helpers bound to the unchanged native validation/measurement implementation. Retain corrected supplemental logs separately; no raw records rewritten." }
FileUtils.cp(__FILE__, campaign)
File.write(File.join(campaign, "benchmark-export-template-reuse-v2.json"), JSON.pretty_generate(report) + "\n", mode: "wx")
puts JSON.pretty_generate(report.reject { |key, _| key == "bindings" })
