# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "open3"
require "time"

scratch = File.dirname(__FILE__)
campaign = "/home/petert/llm_para_campaigns/20261014-212207-sonnet55-medium/evaluation"
supplemental = "/home/petert/llm_timing_audit/20261015-sonnet55-mpi-split-supplemental"
receipt = []
derive = lambda do |source, name, mapping|
  destination = File.join(scratch, name)
  raise "Already exists: #{name}" if File.exist?(destination)
  bytes = File.binread(source)
  mapping.each do |before, after|
    raise "Missing template marker: #{before}" unless bytes.include?(before)
    bytes = bytes.gsub(before, after)
  end
  File.binwrite(destination, bytes)
  receipt << { "file" => name, "template" => source,
    "template_sha256" => Digest::SHA256.file(source).hexdigest,
    "adapted_sha256" => Digest::SHA256.file(destination).hexdigest }
end
derive.call("/home/petert/llm_para_campaigns/20261006-204623-sol61-medium-xhigh/evaluation/finalize-supplemental.rb",
  "finalize-supplemental.rb", {
    "/tmp/sol61-evaluation-20261010.xL0RJx" => scratch,
    "20261010-sol61" => "20261015-sonnet55",
    "qtclustering_gpt-6.1-sol-medium_hybrid_r2" => "qtclustering_claude-sonnet-5.5-cc-medium_hybrid_r1"
  })
derive.call(File.join(scratch, "verify-audit-completion.rb"), "verify-audit-resolution.rb", {
  '  "#{primary}-priority" => ["gpt-5.6-luna", "high"],' =>
    "  \"\#{primary}-mpi-split-supplemental\" => [\"gpt-6.1-sol\", \"xhigh\"],\n  \"\#{primary}-priority\" => [\"gpt-5.6-luna\", \"high\"],",
  '[primary, "#{primary}-qtclustering"].each do |root|' => '[primary, "#{primary}-qtclustering", "#{primary}-mpi-split-supplemental"].each do |root|',
  'audit-completion-review.json' => 'audit-resolution-review.json'
})
changes = {
  "correction-pilot-driver.rb" => {
    'audit-completion-review.json' => 'audit-resolution-review.json',
    '[audit, boundary].each do |root|' => '[audit, boundary, "#{audit}-mpi-split-supplemental"].each do |root|',
    'overlay_roots: [boundary]' => 'overlay_roots: [boundary, "#{audit}-mpi-split-supplemental"]'
  },
  "prepare-corrected-checkout.rb" => { 'audit-completion-review.json' => 'audit-resolution-review.json' },
  "canary-driver.rb" => { 'audit-completion-review.json' => 'audit-resolution-review.json' },
  "benchmark-driver.rb" => {},
  "verify-benchmark-records.rb" => {}
}
changes.each do |name, mapping|
  path = File.join(scratch, name)
  before = File.binread(path)
  persistent = File.join(campaign, name)
  raise "Prepared driver changed: #{name}" unless File.binread(persistent) == before
  archive = name.sub(/\.rb\z/, "-before-supplemental.rb")
  raise "Prior driver already archived: #{archive}" if File.exist?(File.join(campaign, archive))
  FileUtils.cp(path, File.join(campaign, archive))
  after = before
  mapping.each do |old, replacement|
    raise "Missing driver marker: #{old}" unless after.include?(old)
    after = after.gsub(old, replacement)
  end
  if %w[canary-driver.rb benchmark-driver.rb verify-benchmark-records.rb].include?(name)
    marker = /^require [^\n]+\n/
    raise "Missing pipeline loader" unless after.match?(marker)
    guard = "\nraise \"Pinned supplemental MPI library changed\" unless LocalEvaluation.sha256_file(\"/usr/lib/x86_64-linux-gnu/libmpi.so.40.30.6\") == \"9055018b12757e830591aa0283e485e471f1f2a06d3bc0dd5fb35ab00386c172\"\n"
    after = after.sub(marker) { |line| line + guard }
  end
  File.binwrite(path, after)
  receipt << { "file" => name, "previous_sha256" => Digest::SHA256.hexdigest(before),
    "archived_previous" => archive, "adapted_sha256" => Digest::SHA256.hexdigest(after) }
end
receipt.each do |row|
  path = File.join(scratch, row.fetch("file"))
  out, err, status = Open3.capture3("ruby", "-c", path)
  raise "Syntax error: #{out}#{err}" unless status.success?
  FileUtils.cp(path, File.join(campaign, row.fetch("file")))
end
report = { "created_at" => Time.now.utc.iso8601,
  "reason" => "One genuine cross-audit timing disagreement needs the existing focused MPI-implementation adjudication workflow. Earlier decisions and gates remain unchanged; a new resolved gate is mandatory before corrections.",
  "supplemental_root" => supplemental, "files" => receipt,
  "native_measurement_settings_changed" => false, "generated_program_runs" => 0 }
File.write(File.join(campaign, "supplemental-driver-amendment.json"), JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report)
