#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"

options = { root: File.expand_path("../..", __dir__) }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby analysis/src/check_winner_reviews.rb [--root=PATH] [--local-evaluation=PATH]"
  parser.on("--root=PATH") { |value| options[:root] = File.expand_path(value) }
  parser.on("--local-evaluation=PATH") { |value| options[:native] = File.expand_path(value) }
end.parse!

root = options.fetch(:root)
notes = File.join(root, "analysis/notes")
snapshot = JSON.parse(File.read(File.join(notes, "2026-10-02-winner-review-context.json")))
raise "unsupported snapshot" unless snapshot.fetch("schema_version") == 1
reviews = snapshot.fetch("reviews")
raise "review selection changed" unless reviews.size == 29 && reviews.keys.grep(/_gpt-6-/).size == 5

reviews.each do |id, review|
  path = File.join(root, review.fetch("note_path"))
  markdown = File.read(path)
  raise "wrong title: #{id}" unless markdown.lines.first.chomp == "# `#{id}`"
  %w[Scope Finding Interpretation].each do |section|
    raise "missing #{section}: #{id}" unless markdown.include?("\n## #{section}\n\n")
  end
  %w[Close-group\ comparison Correctness\ and\ timing].each do |section|
    raise "missing #{section}: #{id}" unless markdown.include?("\n## #{section}\n\n")
  end
  raise "obsolete structure: #{id}" if markdown.match?(/^## (Non-decisions|Limits and release decision|Scope and evidence)$/)
  times = review.fetch("times_ms")
  raise "wrong median: #{id}" unless times.size == 5 && times.sort[2] == review.fetch("median_ms")
  top = review.fetch("top")
  raise "unsorted peers: #{id}" unless top == top.sort_by { |r| [r.fetch("median_ms"), r.fetch("id")] }
  top.each do |peer|
    raise "wrong peer median: #{peer.fetch('id')}" unless peer.fetch("times_ms").sort[2] == peer.fetch("median_ms")
  end
  raise "wrong rank: #{id}" unless top.fetch(review.fetch("rank") - 1).fetch("id") == id
  pin = snapshot.fetch("source_pins").fetch(id)
  raise "wrong source pin: #{id}" unless pin.fetch("commit") == review.fetch("source_commit") && pin.fetch("path") == review.fetch("source_path")
  markdown.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |link|
    next if link.match?(/\A(?:https?:|#)/)
    target = File.expand_path(link.split("#", 2).first, File.dirname(path))
    raise "broken local link: #{id}: #{link}" unless target.start_with?("#{root}/") && File.file?(target)
  end
end

checked = skipped = 0
snapshot.fetch("inputs").each do |input|
  base = input.fetch("root") == "artifact" ? root : options[:native]
  unless base
    skipped += 1
    next
  end
  path = File.join(base, input.fetch("path"))
  raise "changed benchmark input: #{path}" unless Digest::SHA256.file(path).hexdigest == input.fetch("sha256")
  checked += 1
end

diagnostic = JSON.parse(File.read(File.join(notes, snapshot.fetch("diagnostic"))))
executions = diagnostic.fetch("executions")
raise "diagnostic execution set changed" unless executions.size == 15 && executions.all? { |e| e.fetch("exit_code").zero? }
diagnostic.fetch("variants").each do |name, variant|
  runs = executions.select { |e| e.fetch("variant") == name }
  raise "diagnostic phases missing: #{name}" unless runs.map { |e| e.fetch("label") }.sort == %w[correctness measured-1 measured-2 measured-3 warmup].sort
  measured = runs.select { |e| e.fetch("label").start_with?("measured-") }.map { |e| e.fetch("reported_ms") }
  raise "diagnostic median mismatch: #{name}" unless measured == variant.fetch("times_ms") && measured.sort[1] == variant.fetch("median_ms")
  next if name == "baseline"
  raise "diagnostic validation failed: #{name}" unless variant.fetch("correctness_comparison").fetch("passed")
  patch = File.join(notes, variant.fetch("patch"))
  raise "diagnostic patch changed: #{name}" unless Digest::SHA256.file(patch).hexdigest == variant.fetch("patch_sha256")
end

puts "Winner review checks passed: #{reviews.size} notes; #{checked} unchanged benchmark inputs; #{skipped} external inputs not requested."
puts "Diagnostic: 15 successful executions; patches, sample vectors and medians agree."
diagnostic.fetch("variants").each do |name, variant|
  puts "  #{name}: #{variant.fetch('median_ms')} ms"
end
puts "Reviewed GPT-6 winners (ms):"
reviews.select { |id, _| id.include?("_gpt-6-") }.sort.each do |id, review|
  puts "  #{id}: #{review.fetch('median_ms')} (next: #{review.fetch('top').fetch(1).fetch('median_ms')})"
end
