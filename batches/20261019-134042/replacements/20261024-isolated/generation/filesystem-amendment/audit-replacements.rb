# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "tmpdir"
require "zlib"
require "time"
require "/home/petert/llm_eval/experiment/tools/audit_generation_access"
campaign = "/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high"
amendment = File.join(campaign, "amendments/20261023-filesystem-isolation")
ids = JSON.parse(File.read(File.join(amendment, "amendment.json"))).fetch("affected_observations")
completion = JSON.parse(File.read(File.join(amendment, "completion.json")))
batch = "20261019-134042"
source = File.join("/home/petert/llm_para_experiments", batch)
target = File.join(amendment, "replacement-marker-scan.json.gz")
raise "Scan already exists" if File.exist?(target)
report = Dir.mktmpdir("deepseek-replacement-marker-scan-", "/tmp") do |scratch|
  selected = File.join(scratch, batch)
  FileUtils.mkdir_p(selected)
  ids.each { |id| File.symlink(File.join(source, id), File.join(selected, id)) }
  GenerationAccessAudit.scan(selected)
end
raise "Audit selection differs" unless report.fetch("observations").map { |r| r.fetch("id") }.sort == ids.sort
report["scope"] = source
report["scope_run_ids"] = ids
report["source_commit"] = completion.fetch("source_commit")
Zlib::GzipWriter.open(target) { |gz| gz.mtime = 0; gz.write(JSON.pretty_generate(report) + "\n") }
FileUtils.cp(__FILE__, File.join(amendment, "audit-replacements.rb"))
puts JSON.pretty_generate(report.slice("transcripts_scanned", "candidate_observations", "source_commit").merge(
  "retained_at" => target, "sha256" => Digest::SHA256.file(target).hexdigest,
  "candidates" => report.fetch("observations").filter_map { |r| next if r.fetch("candidate_events").empty?;
    { "id" => r.fetch("id"), "events" => r.fetch("candidate_events").map { |e| e.slice("line", "tool", "markers", "status", "exit_code") } } }))
