# frozen_string_literal: true

# Bind the retained exporter to the exact orchestration snapshot used by the run.
# The frozen native pipeline and its scientific settings are not changed.
require "digest"
require "json"
require "fileutils"
require "time"

scratch = File.dirname(__FILE__)
evaluation = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/evaluation"
source = File.join(scratch, "experiment/tools/timing_audit/bin/export_benchmark_batch.rb")
destination = File.join(scratch, "benchmark-export.rb")
driver = File.join(scratch, "export-completed-batch.rb")
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
old_driver = File.binread(driver)
marker = "require #{source.delete_suffix('.rb').inspect}"
raise "Missing driver dependency" unless old_driver.scan(marker).size == 1
new_driver = old_driver.sub(marker, "require #{destination.delete_suffix('.rb').inspect}")
retained_driver = File.join(evaluation, File.basename(driver))
raise "Retained pending driver differs" unless File.binread(retained_driver) == old_driver
FileUtils.cp(driver, File.join(evaluation, "export-completed-batch-before-export-binding.rb"))
File.binwrite(destination, adapted)
File.binwrite(driver, new_driver)
[destination, driver, __FILE__].each { |path| FileUtils.cp(path, evaluation) }
receipt = {
  "prepared_at" => Time.now.utc.iso8601,
  "source" => source, "source_sha256" => Digest::SHA256.hexdigest(before),
  "execution_snapshot" => destination, "execution_snapshot_sha256" => Digest::SHA256.hexdigest(adapted),
  "orchestration_sha256" => Digest::SHA256.file(File.join(scratch, "benchmark-orchestration.rb")).hexdigest,
  "pending_driver_before_sha256" => Digest::SHA256.hexdigest(old_driver),
  "pending_driver_after_sha256" => Digest::SHA256.hexdigest(new_driver),
  "changes" => "Two exporter require paths bind the campaign's exact benchmark orchestration and the unchanged frozen timing-correction exporter. The pending export driver loads this snapshot. No export logic, native pipeline, measurements or configurations change."
}
File.write(receipt_path, JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt)
