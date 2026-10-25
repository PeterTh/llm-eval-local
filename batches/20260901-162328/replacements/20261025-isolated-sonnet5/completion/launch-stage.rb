# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "time"
stage = ARGV.fetch(0)
drivers = { "correction" => "correction-driver.rb", "revalidation" => "revalidation-driver.rb",
  "canary" => "canary-driver.rb", "benchmark" => "benchmark-driver.rb" }
raise "Unknown stage" unless drivers.key?(stage)
evidence = "/home/petert/llm_para_campaigns/20261025-143725-sonnet5-isolated-replacements/evaluation"
plan = JSON.parse(File.read(File.join(evidence, "campaign.json")))
scratch = plan.fetch("scratch_root")
driver = File.join(scratch, drivers.fetch(stage))
raise "Persistent/frozen driver mismatch" unless File.binread(driver) == File.binread(File.join(evidence, drivers.fetch(stage)))
receipt = File.join(evidence, "#{stage}-launch.json")
raise "Stage already launched" if File.exist?(receipt)
case stage
when "correction"
  audit = JSON.parse(File.read(File.join(evidence, "audit-completion-review.json")))
  raise "Unresolved audit" unless audit.fetch("passed") && audit.fetch("unresolved").empty?
  prior = JSON.parse(File.read(File.join(evidence, "correction-template-reuse.json")))
  raise "Correction driver changed" unless Digest::SHA256.file(driver).hexdigest == prior.fetch("driver_sha256")
when "revalidation"
  commit = JSON.parse(File.read(File.join(evidence, "correction-commit.json")))
  raise "Incorrect correction source parent" unless commit.fetch("original_commit") == plan.fetch("original_source_commit")
when "canary"
  revalidation = JSON.parse(File.read(File.join(evidence, "revalidation-completion-review.json")))
  raise "Revalidation failed" unless revalidation.fetch("verification") == "passed"
  push = JSON.parse(File.read(File.join(evidence, "source-correction-push.json")))
  raise "Corrected source not retained" unless push.fetch("published_commit") == push.fetch("corrected_commit")
when "benchmark"
  gate = JSON.parse(File.read(File.join(evidence, "benchmark-canary-gate.json")))
  raise "Canary gate failed" unless gate.fetch("quality_gate") == "passed"
end
pids, status = Open3.capture2("pgrep", "-u", "llmtest")
raise "Generation account busy" unless status.exitstatus == 1 && pids.empty?
unit = "llm-sonnet5-isolated-#{stage}-20261025.service"
log = File.join(evidence, "#{stage}.log")
raise "Log already exists" if File.exist?(log)
command = ["systemd-run", "--user", "--unit=#{unit}", "--property=Type=exec",
  "--property=WorkingDirectory=#{scratch}", "--setenv=PATH=/home/petert/.local/bin:/usr/local/cuda/bin:/usr/local/bin:/usr/bin:/bin",
  "--property=StandardOutput=append:#{log}", "--property=StandardError=append:#{log}", "/usr/bin/ruby", driver]
raise "Stage launch failed" unless system(*command)
report = { "launched_at" => Time.now.utc.iso8601, "stage" => stage, "unit" => unit,
  "driver_sha256" => Digest::SHA256.file(driver).hexdigest, "command" => command,
  "scope" => "Affected replacements only; preserve all unrelated observations and inherited execution settings." }
File.write(receipt, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, File.join(evidence, "launch-stage.rb"))
puts JSON.pretty_generate(report.except("command"))
