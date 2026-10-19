# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "time"

campaign = "/home/petert/llm_para_campaigns/20261018-224015-luna6-opencode-medium/evaluation"
gate_path = File.join(campaign, "correction-revision-1.json")
gate = JSON.parse(File.read(gate_path))
raise "Revision not accepted" unless gate.fetch("passed") && gate.fetch("accepted_corrections") == 39 &&
  gate.fetch("prior_evidence_unchanged") && gate.fetch("reused_independent_reviews") == 38
progress = JSON.parse(File.read(File.join(campaign, "correction-revision-progress.json")))
raise "Revision progress incomplete" unless progress.fetch("phase") == "awaiting_correction_commit_review" && progress.fetch("unresolved_ids").empty?
target = File.join(campaign, "correction-followup-rebinding.json")
raise "Followup already rebound" if File.exist?(target)
mapping = gate.fetch("prior_roots").to_h { |label, old| [old, gate.fetch("evidence_roots").fetch(label)] }.merge(
  "correction-full-progress.json" => "correction-revision-progress.json",
  "llm-luna6-oc-correction-full-20261019.service" => "llm-luna6-oc-correction-revision-20261019.service"
)
pattern = Regexp.union(mapping.keys.sort_by { |key| -key.size })
names = %w[prepare-corrected-checkout.rb commit-corrections.rb launch-measurement-stage.rb export-completed-batch.rb]
records = names.map do |name|
  source = File.join(__dir__, name)
  previous = File.binread(source)
  persistent = File.join(campaign, name)
  raise "Driver copies differ" if File.exist?(persistent) && File.binread(persistent) != previous
  backup = File.join(campaign, name.sub(/\.rb\z/, "-before-revision-1.rb"))
  raise "Driver backup exists" if File.exist?(backup)
  File.binwrite(backup, previous)
  revised = previous.gsub(pattern) { |old| mapping.fetch(old) }
  raise "No revised binding in #{name}" if revised == previous
  File.binwrite(source, revised)
  raise "Syntax error #{name}" unless system("ruby", "-c", source)
  File.binwrite(persistent, revised)
  { "file" => name, "before_sha256" => Digest::SHA256.hexdigest(previous), "after_sha256" => Digest::SHA256.hexdigest(revised), "retained_original" => backup }
end
record = {
  "rebound_at" => Time.now.utc.iso8601, "revision_gate_sha256" => Digest::SHA256.file(gate_path).hexdigest,
  "mapping" => mapping, "drivers" => records,
  "policy" => "Only operational correction evidence roots and the completed correction-stage gate change. Native validation, benchmark execution, eligibility and measurement settings are unchanged; prior drivers and rejected evidence are retained."
}
File.write(target, JSON.pretty_generate(record) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(record)
