# frozen_string_literal: true
require 'csv'
require 'json'
require 'digest'

root = File.expand_path('../..', __dir__)
paths = Dir[File.join(root, 'analysis/notes/*-fable51-medium-winner-context.json')]
raise 'Expected exactly one Fable winner context' unless paths.size == 1
context = JSON.parse(File.read(paths.first))
reviews = context.fetch('reviews')
winners = JSON.parse(File.read(File.join(root, 'release/winners.json')))
current = winners.select { |row| row.fetch('id').include?('_claude-fable-5.1-cc-medium_') }
raise 'Unreviewed Fable winner' unless (current.map { |row| row.fetch('id') } - reviews.keys).empty?
current.each do |winner|
  review = reviews.fetch(winner.fetch('id'))
  raise 'Reviewed measurement changed' unless review.fetch('times_ms') == winner.fetch('times_ms') &&
    review.fetch('median_ms') == winner.fetch('median_ms')
end
reviews.each do |id, review|
  raise 'Wrong review family' unless id.include?('_claude-fable-5.1-cc-medium_')
  path = File.join(root, review.fetch('note_path'))
  note = File.read(path)
  raise 'Review title differs' unless note.lines.first.chomp == "# `#{id}`"
  ['Scope', 'Finding', 'Close-group comparison', 'Correctness and timing', 'Interpretation'].each do |section|
    raise "Missing #{section}" unless note.include?("\n## #{section}\n\n")
  end
  raise 'Obsolete review filler' if note.match?(/^## (Non-decisions|Limits and release decision|Scope and evidence)$/)
  (review.fetch('top') + [review.fetch('previous')]).each do |peer|
    pin = context.fetch('source_pins').fetch(peer.fetch('id'))
    raise 'Review source pin differs' unless pin.fetch('commit') == peer.fetch('source_commit') &&
      pin.fetch('path') == peer.fetch('source_path')
    raise 'Review peer median differs' unless peer.fetch('times_ms').sort[2] == peer.fetch('median_ms')
    raise 'Missing pinned source files' if pin.fetch('files').empty?
  end
  note.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |link|
    next if link.start_with?('https:', '#')
    target = File.expand_path(link.split('#', 2).first, File.dirname(path))
    raise 'Broken review link' unless target.start_with?(root + '/') && File.file?(target)
  end
end
context.fetch('benchmark_inputs').each do |relative, digest|
  raise 'Review benchmark evidence changed' unless Digest::SHA256.file(File.join(root, relative)).hexdigest == digest
end
puts "Fable 5.1 winner reviews verified: #{reviews.size}; #{current.size} current winners; measurements, source pins and context agree."
