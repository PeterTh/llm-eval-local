#!/usr/bin/env ruby
# frozen_string_literal: true
require 'csv'
require 'digest'
require 'json'

root = File.expand_path('../..', __dir__)
snapshot = JSON.parse(File.read(File.join(root, 'analysis/notes/2026-10-11-sol61-winner-context.json')))
rows = CSV.read(File.join(root, 'release/scored_results.csv'), headers: true).to_h do |row|
  ["#{row['benchmark']}_#{row['model']}_#{row['par_type']}_r#{row['run']}", row]
end
reviews = snapshot.fetch('reviews')
raise 'Wrong review scope' unless reviews.size == 7 && reviews.keys.all? { |id| id.match?(/_gpt-6\.1-sol-(?:medium|xhigh)_/) }
raise 'Wrong baseline scope' unless snapshot.fetch('unchanged_prior_programs') == 6160 && snapshot.fetch('prior_programs_rescored') == 97
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

diagnostic = JSON.parse(File.read(File.join(root, 'analysis/notes/2026-10-11-sol61-spmv-diagnostic.json')))
pin = snapshot.fetch('source_pins').fetch(diagnostic.fetch('program_id'))
raise 'Wrong diagnostic source' unless diagnostic.fetch('source_commit') == pin.fetch('commit') &&
  diagnostic.fetch('variants').fetch('baseline').fetch('source_sha256') == pin.fetch('files').fetch('spmv/spmv.cpp')
patch = File.join(root, 'analysis/notes', diagnostic.fetch('patch'))
raise 'Changed diagnostic patch' unless Digest::SHA256.file(patch).hexdigest == diagnostic.fetch('patch_sha256')
raise 'Diagnostic incomplete' unless diagnostic.fetch('completed_at') && diagnostic.fetch('execution_count') == 10 && diagnostic.fetch('executions').size == 10
raise 'Diagnostic correctness failed' unless diagnostic.fetch('correctness_comparison').fetch('passed')
raise 'Wrong diagnostic configuration' unless diagnostic.fetch('benchmark_args') == %w[-n 10000 -s 40 -i 50000]
raise 'Unexpected diagnostic variants' unless diagnostic.fetch('variants').keys.sort == %w[baseline scalar]
diagnostic.fetch('variants').each do |variant, info|
  executions = diagnostic.fetch('executions').select { |row| row.fetch('variant') == variant }
  raise 'Diagnostic execution scope changed' unless executions.map { |row| row.fetch('label') }.sort == %w[correctness measurement-1 measurement-2 measurement-3 warmup]
  raise 'Diagnostic failure' unless info.fetch('build_success') && executions.all? { |row| row.fetch('success') && row.fetch('exit_code').zero? && !row.fetch('timed_out') }
  samples = executions.select { |row| row.fetch('label').start_with?('measurement-') }.map { |row| row.fetch('reported_ms') }
  raise 'Diagnostic samples changed' unless samples == info.fetch('times_ms') && samples.sort[1] == info.fetch('median_ms')
end
puts "Sol 6.1 review checks passed: #{reviews.size} notes, source pins, links, retained comparisons and 10 bounded diagnostic executions."
