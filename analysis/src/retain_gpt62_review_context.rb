# frozen_string_literal: true
require 'json'
require 'csv'
require 'digest'
require 'fileutils'
require 'open3'
require 'time'

root = File.expand_path('../..', __dir__)
abort 'Usage: retain_gpt62_review_context.rb EVALUATION_DIRECTORY' unless ARGV.size == 1
evaluation = File.expand_path(ARGV.first)
destination = File.join(root, 'analysis/notes/2026-11-25-gpt62-medium-winner-context.json')
raise 'Context already retained' if File.exist?(destination)
pre_path = File.join(evaluation, 'winner-review-context-preintegration.json')
context = JSON.parse(File.read(pre_path))
baseline = context.fetch('baseline_commit')
old_csv, status = Open3.capture2('git', '-C', root, 'show', "#{baseline}:release/scored_results.csv")
raise 'Cannot read baseline' unless status.success?
identify = ->(row) { "#{row['benchmark']}_#{row['model']}_#{row['par_type']}_r#{row['run']}" }
old = CSV.parse(old_csv, headers: true).to_h { |row| [identify.call(row), row.to_h] }
current = CSV.read(File.join(root, 'release/scored_results.csv'), headers: true).to_h { |row| [identify.call(row), row.to_h] }
raise 'Unexpected transition population' unless old.size == 9020 && current.size == 9460
score_changes = []
old.each do |id, before|
  after = current.fetch(id)
  fields = (before.keys | after.keys) - ['overall_score']
  raise "Historical observation changed: #{id}" unless fields.all? { |key| before[key].to_s == after[key].to_s }
  if before.fetch('overall_score') != after.fetch('overall_score')
    score_changes << { 'id' => id, 'before' => before.fetch('overall_score').to_i, 'after' => after.fetch('overall_score').to_i }
  end
end
changed, status = Open3.capture2('git', '-C', root, 'diff', '--name-only', baseline, '--', 'data', 'batches', 'metadata')
raise 'Historical raw evidence changed' unless status.success? && changed.lines.all? { |line| line.start_with?('batches/20261123-155235/', 'metadata/codex-usage/20261123-155235.') }
winners = JSON.parse(File.read(File.join(root, 'release/winners.json')))
actual_new = winners.select { |row| row.fetch('id').include?('_gpt-6.2-') }.map { |row| row.fetch('id') }.sort
raise 'New winners differ' unless actual_new == context.fetch('new_winner_ids').sort
reviews = context.fetch('cells').select { |_, row| row.fetch('new_winner') }.to_h do |cell, record|
  winner = record.fetch('current')
  id = winner.fetch('id')
  actual = winners.find { |row| row.fetch('id') == id }
  raise 'Reviewed measurements differ' unless actual.fetch('times_ms') == winner.fetch('times_ms') && actual.fetch('median_ms') == winner.fetch('median_ms')
  [id, winner.merge('cell' => cell, 'note_path' => "analysis/notes/individual/#{id}.md", 'previous' => record.fetch('previous'), 'top' => record.fetch('top'))]
end
context['reviews'] = reviews
context['finalized_at'] = Time.now.utc.iso8601
context['historical_observation_guard'] = { 'checked' => old.size, 'unchanged_except_overall_score' => true,
  'baseline_scored_csv_sha256' => Digest::SHA256.hexdigest(old_csv), 'joint_score_changes' => score_changes }
context['retention_script_sha256'] = Digest::SHA256.file(__FILE__).hexdigest
context['preintegration_context_sha256'] = Digest::SHA256.file(pre_path).hexdigest
context['benchmark_inputs'] = Dir[File.join(root, 'batches/20261123-155235/benchmark/records/*/*.jsonl')].sort.to_h do |path|
  [path.delete_prefix(root + '/'), Digest::SHA256.file(path).hexdigest]
end
native = '/home/petert/llm_para_local_evaluation/20261125-gpt62-astra-sol-medium-validation-observer-v5'
id = 'roomsim_gpt-6.2-sol-medium_hybrid_r1'
context['roomsim_root_phase_evidence'] = 5.times.map do |index|
  path = File.join(native, 'benchmark', id, "benchmark_#{index}_stdout.log")
  stdout = File.read(path)
  { 'sample' => index, 'stdout_sha256' => Digest::SHA256.file(path).hexdigest,
    'phase_lines' => stdout.lines.grep(/(?:Precomputation|Simulation|Distance computation|Total computation) time:/).map(&:strip) }
end
context['default_visible_selection'] = JSON.parse(File.read(File.join(evaluation, 'default-visible-set-selection.json')))
File.write(destination, JSON.pretty_generate(context) + "\n")
%w[winner-review-context.rb test-winner-review-context.rb winner-review-context-preintegration.json default-visible-set-selection.json].each do |name|
  FileUtils.cp(File.join(evaluation, name), File.join(root, 'batches/20261123-155235/completion', name))
end
puts "Retained #{reviews.size} reviews; #{old.size} prior observations unchanged apart from #{score_changes.size} joint-score changes."
