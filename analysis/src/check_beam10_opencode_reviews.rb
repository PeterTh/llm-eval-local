# frozen_string_literal: true
require 'json'
require 'digest'

root = File.expand_path('../..', __dir__)
context = JSON.parse(File.read(File.join(root, 'analysis/notes/2026-10-30-beam10-opencode-winner-context.json')))
winners = JSON.parse(File.read(File.join(root, 'release/winners.json')))
raise 'Beam winner review scope changed' unless context.fetch('reviews').empty? &&
  winners.none? { |row| row.fetch('id').include?('_beam-1.0-oc-medium_') }
raise 'Unexpected Beam source review pins' unless context.fetch('source_pins').empty?
raise 'Historical observation scope changed' unless context.fetch('unchanged_prior_programs') == 8133 &&
  context.fetch('historical_external_validation_failures').size == 7
context.fetch('benchmark_inputs').each do |relative, digest|
  raise "Review benchmark evidence changed: #{relative}" unless Digest::SHA256.file(File.join(root, relative)).hexdigest == digest
end
puts 'Beam winner review scope verified: no new winners; benchmark evidence and prior-observation scope agree.'
