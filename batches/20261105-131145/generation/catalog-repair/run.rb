# frozen_string_literal: true
require "json"
require "digest"
$stdout.sync = true
$stderr.sync = true
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
runtime = manifest.fetch("working_directory")
manifest.fetch("files").each do |relative, digest|
  raise "Launch snapshot changed: #{relative}" unless Digest::SHA256.file(File.join(runtime, relative)).hexdigest == digest
end
manifest.fetch("benchmark_files").each do |relative, digest|
  raise "Sequential input changed: #{relative}" unless Digest::SHA256.file(File.join(__dir__, "benchmarks", relative)).hexdigest == digest
end
binary = manifest.fetch("codex_binary")
raise "Codex executable changed" unless Digest::SHA256.file(binary).hexdigest == manifest.fetch("codex_binary_sha256")
manifest.fetch("codex_companions").each_value do |entry|
  raise "Codex companion changed" unless Digest::SHA256.file(entry.fetch("path")).hexdigest == entry.fetch("sha256")
end
raise "Production budget required" unless ARGV.include?("--production") && !ARGV.include?("--smoke")
raise "Campaign identity differs" unless ARGV.include?("--continue=#{manifest.fetch('campaign_id')}")
raise "Wrong requested profile" unless manifest.fetch("models") == {
  "gpt-6.1-terra-ultra" => { "model" => "gpt-6.1-terra", "reasoning_effort" => "ultra" } }
if ARGV.include?("--run") && !manifest.fetch("full_campaign_authorized")
  ids_arg = ARGV.find { |arg| arg.start_with?("--run-ids=") }
  raise "Pilot requires explicit observation selection" unless ids_arg
  selected = File.readlines(ids_arg.split("=", 2).last, chomp: true)
  raise "Only the four pilot observations are authorized" unless !selected.empty? && (selected - manifest.fetch("preflight_ids")).empty?
end
ENV["LLM_EVAL_CODEX_BINARY"] = binary
catalog = manifest.fetch("codex_model_catalog")
raise "Frozen catalog changed" unless Digest::SHA256.file(catalog.fetch("path")).hexdigest == catalog.fetch("sha256")
raise "Frozen catalog receipt changed" unless Digest::SHA256.file(catalog.fetch("path") + ".receipt.json").hexdigest == catalog.fetch("receipt_sha256")
ENV["LLM_EVAL_CODEX_MODEL_CATALOG"] = catalog.fetch("path")
ENV["LLM_EVAL_HARNESS"] = "codex"
ENV["LLM_EVAL_MODELS"] = manifest.fetch("models").keys.join(",")
Dir.chdir(runtime)
load File.join(runtime, "experiment.rb")
