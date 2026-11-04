#!/usr/bin/env ruby
# frozen_string_literal: true

# Rebuild this release-specific comparison from the preceding Git revision.
# Requires full repository history, but executes no evaluated program.
require 'csv'
require 'digest'
require 'json'
require 'open3'
require 'set'

root = File.expand_path('../..', __dir__)
baseline = 'c75207d5608801d820eceffe4ffeae6576e4be51'
git = lambda do |*args|
  out, err, status = Open3.capture3('git', '-C', root, *args)
  raise err unless status.success?
  out
end
id = ->(row) { "#{row.fetch('benchmark')}_#{row.fetch('model')}_#{row.fetch('par_type')}_r#{row.fetch('run')}" }
before_bytes = git.call('show', "#{baseline}:release/scored_results.csv")
after_bytes = File.read(File.join(root, 'release/scored_results.csv'))
before = CSV.parse(before_bytes, headers: true).to_h { |row| [id.call(row), row.to_h] }
after = CSV.parse(after_bytes, headers: true).to_h { |row| [id.call(row), row.to_h] }
raise 'Observation population changed' unless before.keys == after.keys && after.size == 8580
catalog_path = File.join(root, 'release/catalog.json')
catalog = JSON.parse(File.read(catalog_path))
newly_failed = after.keys.select { |key| before[key]['validation_status'] != after[key]['validation_status'] }.to_set
raise 'Failure count changed' unless newly_failed.size == 175
source_and_accounting = []
after.each do |key, row|
  old = before.fetch(key)
  allowed = ['overall_score']
  if newly_failed.include?(key)
    raise "Unexpected validation transition: #{key}" unless old['validation_status'] == '5' && row['validation_status'] == '4' && row['overall_score'] == '4'
    allowed += %w[validation_status validation_err_string external_validation_case external_validation_evidence]
    allowed += (old.keys | row.keys).grep(/\Abenchmark_/)
    raise "Excluded timing remains eligible: #{key}" unless row['benchmark_success'].nil? && row['benchmark_median_time'].nil?
  end
  fields = (old.keys | row.keys).sort - allowed
  raise "Unrelated fields changed: #{key}" unless fields.all? { |field| old[field] == row[field] }
  source_and_accounting << [key, fields.to_h { |field| [field, row[field]] }]
end
raise 'Archived inputs changed' unless git.call('diff', '--name-only', baseline, '--', 'data', 'batches', 'corrections', 'metadata').empty?
old_winners = git.call('show', "#{baseline}:release/winners.json")
raise 'Winner evidence changed' unless old_winners == File.read(File.join(root, 'release/winners.json'))
failures = newly_failed.to_a.sort.map do |key|
  old, row = before.fetch(key), after.fetch(key)
  { 'id' => key, 'benchmark' => row.fetch('benchmark'), 'model' => row.fetch('model'), 'backend' => row.fetch('par_type'),
    'previous_score' => Integer(old.fetch('overall_score')), 'previously_measured' => old['benchmark_success'] == 'true',
    'previous_median_ms' => old['benchmark_median_time'] && Float(old['benchmark_median_time']),
    'case' => row.fetch('external_validation_case'), 'evidence' => row.fetch('external_validation_evidence'),
    'reason' => row.fetch('validation_err_string') }
end
raise 'Excluded successful count changed' unless failures.count { |row| row.fetch('previously_measured') } == 142
rescores = after.keys.reject { |key| newly_failed.include?(key) }.filter_map do |key|
  next if before[key]['overall_score'] == after[key]['overall_score']
  { 'id' => key, 'previous_score' => Integer(before[key]['overall_score']), 'current_score' => Integer(after[key]['overall_score']) }
end
raise 'Joint rescore count changed' unless rescores.size == 49
summary = lambda do |field|
  failures.group_by { |row| row.fetch(field) }.sort.to_h.transform_values do |rows|
    { 'new_failures' => rows.size, 'previously_measured' => rows.count { |row| row.fetch('previously_measured') } }
  end
end
result = {
  'schema_version' => 1, 'release_date' => catalog.fetch('generated_at'), 'baseline_commit' => baseline,
  'baseline_csv_sha256' => Digest::SHA256.hexdigest(before_bytes),
  'current_csv_sha256' => Digest::SHA256.hexdigest(after_bytes),
  'catalog_sha256' => Digest::SHA256.file(catalog_path).hexdigest,
  'counts' => catalog.fetch('expected'), 'new_failures' => 175, 'excluded_successful_measurements' => 142,
  'unchanged_winners' => 44, 'joint_rescores_outside_exclusions' => 49,
  'original_sources_and_measurements_changed' => false, 'benchmark_runs' => 0,
  'unchanged_fields_sha256' => Digest::SHA256.hexdigest(JSON.generate(source_and_accounting)),
  'by_benchmark' => summary.call('benchmark'), 'by_model' => summary.call('model'),
  'failures' => failures, 'joint_rescores' => rescores
}
destination = File.join(root, 'analysis/notes/2026-11-04-validation-strengthening-impact.json')
File.write(destination, JSON.pretty_generate(result) + "\n")
puts "Verified 175 exclusions, 142 removed successful timings, 49 joint rescores and 44 unchanged winners."
