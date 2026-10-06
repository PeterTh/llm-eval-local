#!/usr/bin/env ruby
# frozen_string_literal: true
require 'csv'
require 'digest'
require 'json'
root = File.expand_path('../..', __dir__)
snapshot = JSON.parse(File.read(File.join(root, 'analysis/notes/2026-10-06-opus55-winner-context.json')))
rows = CSV.read(File.join(root, 'release/scored_results.csv'), headers: true).to_h do |r|
  ["#{r['benchmark']}_#{r['model']}_#{r['par_type']}_r#{r['run']}", r]
end
reviews = snapshot.fetch('reviews')
raise 'Wrong review scope' unless reviews.size == 13 && reviews.keys.all? { |id| id.include?('_claude-opus-5.5-cc-medium_') }
reviews.each do |id, review|
  file = File.join(root, review.fetch('note_path'))
  text = File.read(file)
  raise "Wrong note title #{id}" unless text.lines.first.chomp == "# `#{id}`"
  ['Scope', 'Finding', 'Close-group comparison', 'Correctness and timing', 'Interpretation'].each do |heading|
    raise "Missing #{heading}: #{id}" unless text.include?("\n## #{heading}\n\n")
  end
  raise "Wrong winner #{id}" unless review.fetch('top').first.fetch('id') == id
  review.fetch('top').each do |peer|
    row = rows.fetch(peer.fetch('id'))
    raise "Changed comparison samples #{peer['id']}" unless row.fetch('benchmark_times').split(';').map(&:to_f) == peer.fetch('times_ms')
    raise "Wrong median #{peer['id']}" unless peer.fetch('times_ms').sort[2] == peer.fetch('median_ms')
    pin = snapshot.fetch('source_pins').fetch(peer.fetch('id'))
    raise "Wrong source pin #{peer['id']}" unless pin.fetch('commit') == peer.fetch('source_commit') && pin.fetch('path') == peer.fetch('source_path')
  end
  text.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |link|
    next if link.match?(/\A(?:https?:|#)/)
    target = File.expand_path(link.split('#', 2).first, File.dirname(file))
    raise "Broken note link #{id}: #{link}" unless target.start_with?(root + '/') && File.file?(target)
  end
end
snapshot.fetch('benchmark_inputs').each do |relative, digest|
  raise "Changed review evidence #{relative}" unless Digest::SHA256.file(File.join(root, relative)).hexdigest == digest
end
puts "Opus 5.5 review checks passed: #{reviews.size} notes, source pins, links and retained comparison vectors."
