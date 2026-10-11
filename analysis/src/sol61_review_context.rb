#!/usr/bin/env ruby
# frozen_string_literal: true
require "csv"
require "digest"
require "json"
require "open3"

root = File.expand_path("../..", __dir__)
baseline = "d2675741cb5ac74cea6fd94fb38f46aef11cb4b4"
id = ->(r) { "#{r['benchmark']}_#{r['model']}_#{r['par_type']}_r#{r['run']}" }
summarize = lambda do |r|
  { "id" => id.call(r), "median_ms" => Float(r.fetch("benchmark_median_time")),
    "times_ms" => r.fetch("benchmark_times").split(";").map(&:to_f), "source_path" => r.fetch("source_path"),
    "source_commit" => r["corrected_source_commit"].to_s.empty? ? nil : r["corrected_source_commit"],
    "timing_fixed" => r.fetch("timing_fixed") == "true" }
end
group = lambda do |rows|
  rows.select { |r| r['benchmark_success'] == 'true' }.group_by { |r| "#{r['benchmark']}/#{r['par_type']}" }
    .transform_values { |rs| rs.map { |r| summarize.call(r) }.sort_by { |r| [r['median_ms'], r['id']] } }
end
prior_bytes, status = Open3.capture2("git", "-C", root, "show", "#{baseline}:release/scored_results.csv")
raise "Missing review baseline" unless status.success?
prior = CSV.parse(prior_bytes, headers: true)
current = CSV.read(File.join(root, "release/scored_results.csv"), headers: true)
old_groups, new_groups = [prior, current].map { |rs| group.call(rs) }
catalog = JSON.parse(File.read(File.join(root, "release/catalog.json")))
commits = catalog.fetch("campaigns").to_h { |c| [c.fetch("id"), c.fetch("source_commit")] }
commits['20260805-120633'] = commits.fetch('2026-08-timing-corrected')
generated = ARGV.reject { |arg| arg == '--check' }.first || "/home/petert/llm_para_experiments"
pins = {}
reviews = new_groups.sort.filter_map do |cell, entries|
  winner = entries.first
  next if winner.fetch('id') == old_groups.fetch(cell).first.fetch('id')
  raise "Unexpected winner family" unless winner.fetch('id').match?(/_gpt-6\.1-sol-(?:medium|xhigh)_/)
  peers = (entries.first(8) + [old_groups.fetch(cell).first]).uniq { |r| r.fetch('id') }
  peers.each do |peer|
    path = peer.fetch('source_path')
    batch = path.split('/').first
    commit = peer['source_commit'] || commits[batch] || commits.fetch('2026-08-timing-corrected')
    peer['source_commit'] = commit
    files, ok = Open3.capture2('git', '-C', generated, 'ls-tree', '-r', '--name-only', commit, '--', path)
    raise "Missing source #{path}" unless ok.success? && !files.empty?
    hashes = files.lines.map(&:strip).select { |p| p.match?(/\.(?:cpp|cu|hpp|h)$/) || File.basename(p) == 'CMakeLists.txt' }.to_h do |file|
      bytes, success = Open3.capture2('git', '-C', generated, 'show', "#{commit}:#{file}")
      raise "Missing blob #{file}" unless success.success?
      [file.delete_prefix(path + '/'), Digest::SHA256.hexdigest(bytes)]
    end
    pins[peer.fetch('id')] = { 'commit' => commit, 'path' => path, 'files' => hashes }
  end
  [winner.fetch('id'), { 'cell' => cell, 'note_path' => "analysis/notes/individual/#{winner['id']}.md",
    'previous' => peers.find { |peer| peer.fetch('id') == old_groups.fetch(cell).first.fetch('id') }, 'top' => peers, 'median_ms' => winner['median_ms'],
    'times_ms' => winner['times_ms'], 'source_commit' => winner['source_commit'], 'source_path' => winner['source_path'] }]
end.to_h
old_by_id = prior.to_h { |r| [id.call(r), r] }
old_current = current.select { |r| old_by_id.key?(id.call(r)) }
raise "Prior observation scope changed" unless old_current.size == prior.size && prior.size == 6160
fields = prior.headers - %w[overall_score]
raise "Prior observations changed" unless old_current.all? { |r| fields.all? { |f| r[f] == old_by_id.fetch(id.call(r))[f] } }
inputs = Dir[File.join(root, 'batches/20261006-204623/benchmark/records/*/*.jsonl')].sort.to_h { |p| [p.delete_prefix(root + '/'), Digest::SHA256.file(p).hexdigest] }
context = { 'schema_version' => 1, 'date' => '2026-10-11', 'baseline_commit' => baseline,
  'baseline_scored_csv_sha256' => Digest::SHA256.hexdigest(prior_bytes), 'unchanged_prior_programs' => old_current.size,
  'prior_programs_rescored' => old_current.count { |r| r['overall_score'] != old_by_id.fetch(id.call(r))['overall_score'] },
  'benchmark_inputs' => inputs, 'source_pins' => pins.sort.to_h, 'reviews' => reviews }
destination = File.join(root, 'analysis/notes/2026-10-11-sol61-winner-context.json')
bytes = JSON.pretty_generate(context) + "\n"
if ARGV.include?('--check')
  raise 'Stale Sol 6.1 review context' unless File.binread(destination) == bytes
else
  File.binwrite(destination, bytes)
end
reviews.each { |name, r| puts "#{r['cell']} #{r['top'].first(5).map { |p| p['id'].split('_', 2).last + '=' + p['median_ms'].to_s }.join(' / ')}" }
puts "Unchanged prior observations: #{old_current.size}; joint-threshold score changes: #{context['prior_programs_rescored']}"
