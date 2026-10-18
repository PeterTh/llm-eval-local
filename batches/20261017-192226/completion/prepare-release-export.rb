# frozen_string_literal: true
# Dependency rebinding only; no export, build, test or generated execution.
require "digest"
require "json"
require "fileutils"
require "time"

scratch = __dir__
evaluation = "/home/petert/llm_para_campaigns/20261017-192226-sol61-opencode-medium/evaluation"
source = File.join(scratch, "experiment/tools/timing_audit/bin/export_benchmark_batch.rb")
destination = File.join(scratch, "benchmark-export.rb")
receipt_path = File.join(evaluation, "benchmark-export-template-reuse.json")
raise "Exporter binding already prepared" if File.exist?(destination) || File.exist?(receipt_path)
before = File.binread(source)
adapted = before.dup
{
  'require_relative "benchmark_validation_batch"' => "require #{File.join(scratch, 'benchmark-orchestration').inspect}",
  'require_relative "export_timing_corrections"' => "require #{File.join(scratch, 'experiment/tools/timing_audit/bin/export_timing_corrections').inspect}"
}.each do |old, replacement|
  raise "Missing exporter dependency" unless adapted.scan(old).size == 1
  adapted = adapted.sub(old, replacement)
end
File.binwrite(destination, adapted)
receipt = {
  "prepared_at" => Time.now.utc.iso8601, "source" => source,
  "source_sha256" => Digest::SHA256.hexdigest(before), "execution_snapshot" => destination,
  "execution_snapshot_sha256" => Digest::SHA256.hexdigest(adapted),
  "orchestration_sha256" => Digest::SHA256.file(File.join(scratch, "benchmark-orchestration.rb")).hexdigest,
  "changes" => "Only two require paths rebound to the exact campaign orchestration and unchanged frozen correction exporter. No measurement or export logic changed."
}
[destination, File.join(scratch, "export-completed-batch.rb"), __FILE__].each { |path| FileUtils.cp(path, evaluation) }
File.write(receipt_path, JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt)
