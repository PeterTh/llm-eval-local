# frozen_string_literal: true
require 'json'
require 'digest'

root = File.expand_path('../..', __dir__)
context = JSON.parse(File.read(File.join(root, 'analysis/notes/2026-10-29-terra61-codex-winner-context.json')))
reviews = context.fetch('reviews')
winners = JSON.parse(File.read(File.join(root, 'release/winners.json')))
selected = winners.select { |row| row.fetch('id').include?('_gpt-6.1-terra-medium_') }
raise 'Terra winner review scope differs' unless selected.map { |row| row.fetch('id') }.sort == reviews.keys.sort
selected.each do |winner|
  id = winner.fetch('id')
  review = reviews.fetch(id)
  raise 'Reviewed measurement changed' unless review.fetch('times_ms') == winner.fetch('times_ms') && review.fetch('median_ms') == winner.fetch('median_ms')
  note = File.read(File.join(root, review.fetch('note_path')))
  raise 'Review title differs' unless note.lines.first.chomp == "# `#{id}`"
  ['Scope', 'Finding', 'Close-group comparison', 'Correctness and timing', 'Interpretation'].each do |section|
    raise "Missing #{section}" unless note.include?("\n## #{section}\n\n")
  end
  raise 'Obsolete review filler' if note.match?(/^## (Non-decisions|Limits and release decision|Scope and evidence)$/)
  (review.fetch('top') + [review.fetch('previous')]).each do |peer|
    pin = context.fetch('source_pins').fetch(peer.fetch('id'))
    raise 'Review source pin differs' unless pin.fetch('commit') == peer.fetch('source_commit') && pin.fetch('path') == peer.fetch('source_path')
    raise 'Review peer median differs' unless peer.fetch('times_ms').sort[2] == peer.fetch('median_ms')
  end
  note.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |link|
    next if link.start_with?('https:', '#')
    target = File.expand_path(link.split('#', 2).first, File.dirname(File.join(root, review.fetch('note_path'))))
    raise 'Broken review link' unless target.start_with?(root + '/') && File.file?(target)
  end
end
context.fetch('benchmark_inputs').each do |relative, digest|
  raise 'Review benchmark evidence changed' unless Digest::SHA256.file(File.join(root, relative)).hexdigest == digest
end
puts "Terra winner reviews verified: #{reviews.size}; measurement vectors, source pins and context agree."
