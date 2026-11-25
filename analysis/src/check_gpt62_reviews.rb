# frozen_string_literal: true
require 'json'
require 'digest'
root = File.expand_path('../..', __dir__)
context = JSON.parse(File.read(File.join(root, 'analysis/notes/2026-11-25-gpt62-medium-winner-context.json')))
reviews = context.fetch('reviews')
raise 'Review coverage differs' unless reviews.size == 9 && reviews.keys.sort == context.fetch('new_winner_ids').sort
winners = JSON.parse(File.read(File.join(root, 'release/winners.json')))
winners.select { |row| row.fetch('id').include?('_gpt-6.2-') }.each do |row|
  review = reviews.fetch(row.fetch('id'))
  raise 'Reviewed measurements changed' unless row.fetch('times_ms') == review.fetch('times_ms') && row.fetch('median_ms') == review.fetch('median_ms')
end
reviews.each do |id, review|
  file = File.join(root, review.fetch('note_path'))
  note = File.read(file)
  raise 'Wrong review title' unless note.lines.first.chomp == "# `#{id}`"
  ['Scope', 'Finding', 'Close-group comparison', 'Correctness and timing', 'Interpretation'].each do |section|
    raise 'Missing review section' unless note.include?("\n## #{section}\n\n")
  end
  raise 'Obsolete filler' if note.match?(/^## (Non-decisions|Limits and release decision|Scope and evidence)$/)
  (review.fetch('top') + [review.fetch('previous')]).each do |peer|
    pin = context.fetch('source_pins').fetch(peer.fetch('id'))
    raise 'Peer source pin changed' unless pin.fetch('commit') == peer.fetch('source_commit') && pin.fetch('path') == peer.fetch('source_path') && !pin.fetch('files').empty?
    raise 'Peer median differs' unless peer.fetch('times_ms').sort[2] == peer.fetch('median_ms')
  end
  note.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |link|
    next if link.start_with?('https:', '#')
    target = File.expand_path(link.split('#', 2).first, File.dirname(file))
    raise 'Broken review link' unless target.start_with?(root + '/') && File.file?(target)
  end
end
context.fetch('benchmark_inputs').each do |relative, digest|
  raise 'Review input changed' unless Digest::SHA256.file(File.join(root, relative)).hexdigest == digest
end
probes = JSON.parse(File.read(File.join(root, 'analysis/notes/2026-11-25-gpt62-outlier-probes.json')))
raise 'Incomplete diagnostics' unless probes.fetch('successful') && probes.fetch('experiments').size == 2
probes.fetch('experiments').each do |probe|
  raise 'Diagnostic result disagreement' unless probe.fetch('identical_check_results') && probe.fetch('checks').map { |r| r.fetch('stdout')[/=== RESULTS ===.*?=== END RESULTS ===/m] }.uniq.size == 1
  raise 'Unexpected diagnostic scope' unless probe.fetch('runs').size == 8
  %w[normal disabled].each do |variant|
    runs = probe.fetch('runs').select { |row| row.fetch('variant') == variant }
    raise 'Wrong diagnostic samples' unless runs.count { |row| row.fetch('sample') == 'warmup' } == 1 &&
      runs.reject { |row| row.fetch('sample') == 'warmup' }.map { |row| row.fetch('time_ms') }.sort[1] == probe.fetch('median_ms').fetch(variant)
  end
end
choice = context.fetch('default_visible_selection')
raise 'Visibility discussion unresolved' unless choice.fetch('publication_discussion_resolved') && choice.fetch('selected_visible_count') == 30
puts 'GPT-6.2 reviews verified: 9 notes, source-pinned comparisons, 16 explanatory timing executions and 4 paired correctness executions.'
