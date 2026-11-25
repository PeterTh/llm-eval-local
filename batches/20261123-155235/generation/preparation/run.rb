# frozen_string_literal: true
require "json"
require "digest"
$stdout.sync = $stderr.sync = true
campaign = File.read(File.join(__dir__, "campaign.path")).strip
manifest = JSON.parse(File.read(File.join(campaign, "campaign.json")))
runtime = manifest.fetch("working_directory")
manifest.fetch("files").each { |path, sha| raise "Frozen method changed: #{path}" unless Digest::SHA256.file(File.join(runtime, path)).hexdigest == sha }
manifest.fetch("benchmark_files").each { |path, sha| raise "Frozen input changed: #{path}" unless Digest::SHA256.file(File.join(__dir__, "benchmarks", path)).hexdigest == sha }
binary = manifest.fetch("codex_binary")
raise "Executable changed" unless Digest::SHA256.file(binary).hexdigest == manifest.fetch("codex_binary_sha256")
manifest.fetch("codex_companions").each_value { |row| raise "Companion changed" unless Digest::SHA256.file(row.fetch("path")).hexdigest == row.fetch("sha256") }
catalog = manifest.fetch("codex_model_catalog")
raise "Catalog changed" unless Digest::SHA256.file(catalog.fetch("path")).hexdigest == catalog.fetch("sha256") && Digest::SHA256.file(catalog.fetch("path") + ".receipt.json").hexdigest == catalog.fetch("receipt_sha256")
raise "Production budget required" unless ARGV.include?("--production") && !ARGV.include?("--smoke")
raise "Wrong campaign" unless ARGV.include?("--continue=#{manifest.fetch('campaign_id')}")
raise "Wrong profiles" unless manifest.fetch("models") == %w[astra sol].to_h { |family| ["gpt-6.2-#{family}-medium", {"model"=>"gpt-6.2-#{family}", "reasoning_effort"=>"medium"}] }
ENV["LLM_EVAL_CODEX_BINARY"] = binary
ENV["LLM_EVAL_CODEX_MODEL_CATALOG"] = catalog.fetch("path")
ENV["LLM_EVAL_HARNESS"] = "codex"
ENV["LLM_EVAL_MODELS"] = manifest.fetch("models").keys.join(",")
Dir.chdir(runtime)
load File.join(runtime, "experiment.rb")
