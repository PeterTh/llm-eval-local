# frozen_string_literal: true

require_relative "experiment/tools/timing_audit/lib/timing_audit"
require_relative "experiment/lib/local_evaluation"

scratch = File.dirname(__FILE__)
campaign = "/home/petert/llm_para_campaigns/20261018-224015-luna6-opencode-medium/evaluation"
proposals = "/home/petert/llm_timing_fixes/20261019-luna6-opencode-proposals-revision1"
source = "/home/petert/llm_para_experiments"
destination = File.join(scratch, "corrected")
original_commit = "fd64978a13b9a4f3ac6a5e368972316d0c159aa1"
batch = "20261018-224015"
origin = "git@github.com:PeterTh/llm-eval-generated.git"
raise "Correction checkout already exists" if File.exist?(destination)
gate = JSON.parse(File.read(File.join(campaign, "audit-completion-review.json")))
raise "Unresolved audit" unless gate.fetch("passed") && gate.fetch("unresolved").empty?
progress = JSON.parse(File.read(File.join(campaign, "correction-revision-progress.json")))
raise "Correction reviews not complete" unless progress.fetch("phase") == "awaiting_correction_commit_review" && progress.fetch("unresolved_ids").empty?
inventory = TimingAudit.load_jsonl(File.join(proposals, "inventory.jsonl"))
ids = inventory.map { |row| row.fetch("id") }.sort
raise "Invalid correction selection" unless !ids.empty? && ids.uniq == ids && inventory.all? { |row|
  row.fetch("source_prefix") == File.join(batch, row.fetch("id")) && row.fetch("id").match?(/\A[a-zA-Z0-9_.-]+\z/)
}
TimingAudit.capture!("git", "clone", "--shared", "--no-checkout", source, destination)
TimingAudit.capture!("git", "-C", destination, "sparse-checkout", "init", "--cone")
TimingAudit.capture!("git", "-C", destination, "sparse-checkout", "set", *ids.map { |id| File.join(batch, id) })
TimingAudit.capture!("git", "-C", destination, "checkout", "--detach", original_commit)
TimingAudit.capture!("git", "-C", destination, "remote", "set-url", "origin", origin)
TimingAudit::SourceRepository.new(root: destination, commit: original_commit)
batches, runs = LocalEvaluation::Manifest.discover(destination)
raise "Sparse checkout scope differs" unless batches == [batch] && runs.keys.sort == ids
raise "Original-source link would be invalid" unless TimingAudit.capture!("git", "-C", destination, "remote", "get-url", "origin").strip == origin
report = {
  "prepared_at" => TimingAudit.utc_now, "source_commit" => original_commit,
  "origin" => origin, "checkout" => destination, "records" => ids.size,
  "proposal_inventory_sha256" => TimingAudit.sha256_file(File.join(proposals, "inventory.jsonl")),
  "driver_sha256" => TimingAudit.sha256_file(__FILE__),
  "source_edits_applied" => false, "policy" => "Exactly the accepted proposal selection, clean at the original source revision. One timing-only commit is created by the separate verified commit driver."
}
output = File.join(campaign, "corrected-checkout.json")
raise "Checkout receipt already exists" if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report)
