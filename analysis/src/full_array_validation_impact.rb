#!/usr/bin/env ruby
# frozen_string_literal: true

# Reconstruct this validation-only release transition from archived Git data.
# No evaluated program, model or performance benchmark is executed.
require 'csv'
require 'digest'
require 'json'
require 'open3'
require 'set'

root = File.expand_path('../..', __dir__)
baseline = 'a9d83e86f44b9711bf2750ae5b827570164bbf79'
git = lambda do |*args|
  out, error, status = Open3.capture3('git', '-C', root, *args)
  raise error unless status.success?
  out
end
identity = ->(row) { "#{row.fetch('benchmark')}_#{row.fetch('model')}_#{row.fetch('par_type')}_r#{row.fetch('run')}" }
before_bytes = git.call('show', "#{baseline}:release/scored_results.csv")
after_bytes = File.read(File.join(root, 'release/scored_results.csv'))
before = CSV.parse(before_bytes, headers: true).to_h { |row| [identity.call(row), row.to_h] }
after = CSV.parse(after_bytes, headers: true).to_h { |row| [identity.call(row), row.to_h] }
raise 'Observation population changed' unless before.keys == after.keys && after.size == 8580
catalog_path = File.join(root, 'release/catalog.json')
catalog = JSON.parse(File.read(catalog_path))
receipt_path = 'validation-supplements/20261105-full-array-full/export.json'
receipt = JSON.parse(File.read(File.join(root, receipt_path)))
raise 'Wrong correctness sweep' unless receipt.fetch('kind') == 'full-array-correctness-sweep'
failed = after.keys.select { |id| before[id]['validation_status'] != after[id]['validation_status'] }.to_set
raise 'Release exclusions differ from completed sweep' unless failed.to_a.sort == receipt.fetch('failed_ids')
invariant_fields = []
after.each do |id, row|
  old = before.fetch(id)
  allowed = ['overall_score']
  if failed.include?(id)
    unless old['validation_status'] == '5' && row['validation_status'] == '4' && row['overall_score'] == '4'
      raise "Unexpected validation transition: #{id}"
    end
    allowed += %w[validation_status validation_err_string external_validation_case external_validation_evidence]
    allowed += (old.keys | row.keys).grep(/\Abenchmark_/)
    unless row['benchmark_success'].nil? && row['benchmark_median_time'].nil?
      raise "Excluded performance remains eligible: #{id}"
    end
  end
  fields = (old.keys | row.keys).sort - allowed
  raise "Unrelated fields changed: #{id}" unless fields.all? { |field| old[field] == row[field] }
  invariant_fields << [id, fields.to_h { |field| [field, row[field]] }]
end
unless git.call('diff', '--name-only', baseline, '--', 'data', 'batches', 'corrections', 'metadata').empty?
  raise 'Archived sources, validation, performance or accounting evidence changed'
end
old_winners = JSON.parse(git.call('show', "#{baseline}:release/winners.json"))
new_winners = JSON.parse(File.read(File.join(root, 'release/winners.json')))
cell = ->(row) { row.fetch('cell') }
prior_by_cell = old_winners.to_h { |row| [cell.call(row), row] }
raise 'Winner cell coverage changed' unless new_winners.map(&cell).sort == prior_by_cell.keys.sort
winner_changes = new_winners.filter_map do |winner|
  old = prior_by_cell.fetch(cell.call(winner))
  next if old == winner
  raise 'Unrelated winner changed' unless failed.include?(old.fetch('id')) && !failed.include?(winner.fetch('id'))
  { 'cell' => winner.fetch('cell'), 'previous' => old, 'current' => winner }
end
failures = failed.to_a.sort.map do |id|
  old, row = before.fetch(id), after.fetch(id)
  { 'id' => id, 'benchmark' => row.fetch('benchmark'), 'model' => row.fetch('model'), 'backend' => row.fetch('par_type'),
    'previous_score' => Integer(old.fetch('overall_score')), 'previously_measured' => old['benchmark_success'] == 'true',
    'previous_median_ms' => old['benchmark_median_time'] && Float(old['benchmark_median_time']),
    'case' => row.fetch('external_validation_case'), 'evidence' => row.fetch('external_validation_evidence'),
    'reason' => row.fetch('validation_err_string') }
end
rescores = after.keys.reject { |id| failed.include?(id) }.filter_map do |id|
  next if before[id]['overall_score'] == after[id]['overall_score']
  { 'id' => id, 'previous_score' => Integer(before[id]['overall_score']), 'current_score' => Integer(after[id]['overall_score']) }
end
summary = lambda do |field|
  failures.group_by { |row| row.fetch(field) }.sort.to_h.transform_values do |rows|
    { 'new_failures' => rows.size, 'previously_measured' => rows.count { |row| row.fetch('previously_measured') } }
  end
end
result = {
  'schema_version' => 1, 'release_date' => catalog.fetch('generated_at'), 'baseline_commit' => baseline,
  'baseline_csv_sha256' => Digest::SHA256.hexdigest(before_bytes), 'current_csv_sha256' => Digest::SHA256.hexdigest(after_bytes),
  'catalog_sha256' => Digest::SHA256.file(catalog_path).hexdigest,
  'full_array_receipt' => receipt_path, 'full_array_receipt_sha256' => Digest::SHA256.file(File.join(root, receipt_path)).hexdigest,
  'counts' => catalog.fetch('expected'), 'new_failures' => failures.size,
  'excluded_successful_measurements' => failures.count { |row| row.fetch('previously_measured') },
  'unchanged_winners' => old_winners.size - winner_changes.size, 'winner_changes' => winner_changes,
  'joint_rescores_outside_exclusions' => rescores.size, 'original_sources_and_measurements_changed' => false,
  'benchmark_runs' => 0, 'llm_invocations' => 0,
  'unchanged_fields_sha256' => Digest::SHA256.hexdigest(JSON.generate(invariant_fields)),
  'by_benchmark' => summary.call('benchmark'), 'by_model' => summary.call('model'),
  'failures' => failures, 'joint_rescores' => rescores
}
destination = File.join(root, 'analysis/notes/2026-11-05-full-array-validation-impact.json')
File.write(destination, JSON.pretty_generate(result) + "\n")
puts "Verified #{failures.size} exclusions, #{result.fetch('excluded_successful_measurements')} removed successful timings, #{rescores.size} joint rescores and #{winner_changes.size} winner changes."
