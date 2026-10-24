# frozen_string_literal: true
require 'json'
require 'digest'
require 'fileutils'
require 'time'
campaign = '/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high'
evidence = File.join(campaign, 'amendments/20261023-filesystem-isolation/evaluation')
output = File.join(evidence, 'pricing')
old_path = File.join(campaign, 'pricing/request-context-summary.json')
new_path = File.join(output, 'request-context-summary.json')
old, fresh = [old_path, new_path].map { |p| JSON.parse(File.read(p)).fetch('records') }
ids = File.readlines(File.join(File.dirname(evidence), 'run-ids.txt'), chomp: true).sort
raise 'Context replacement scope differs' unless fresh.map { |r| r.fetch('id') }.sort == ids
records = old.reject { |r| ids.include?(r.fetch('id')) } + fresh
observations = Dir[File.join(campaign, 'observations/*.json')].map { |p| JSON.parse(File.read(p)) }.to_h { |r| [r.fetch('id'), r] }
raise 'Current context coverage differs' unless records.size == 220 && records.map { |r| r.fetch('id') }.sort == observations.keys.sort
records.each do |r|
  observation = observations.fetch(r.fetch('id'))
  raise 'Current context differs from native observation' unless r.fetch('session_id') == observation.fetch('session_id') &&
    r.fetch('token_counts') == observation.fetch('token_counts') && r.fetch('usage_complete') == observation.fetch('usage_complete') &&
    r.fetch('native_session_sha256') == observation.fetch('sha256').fetch('opencode-session.txt')
end
reference = JSON.parse(File.read(File.join(output, 'pricing-reference.json')))
complete = records.select { |r| r.fetch('usage_complete') }
means = reference.fetch('complete_observation_mean_tokens').keys.to_h { |k| [k, complete.sum { |r| r.fetch('token_counts').fetch(k) }.fdiv(complete.size)] }
raise 'Pricing token mix differs' unless means == reference.fetch('complete_observation_mean_tokens')
report = { 'checked_at' => Time.now.utc.iso8601, 'programs' => records.size, 'complete_programs' => complete.size,
  'incomplete_programs' => records.size - complete.size, 'requests' => records.sum { |r| r.fetch('request_count') },
  'maximum_request_input_tokens' => records.map { |r| r.fetch('maximum_request_input_tokens') }.max,
  'maximum_request_output_tokens' => records.map { |r| r.fetch('maximum_request_output_tokens') }.max,
  'cache_write_input_tokens' => records.sum { |r| r.fetch('cache_write_input_tokens') },
  'input_sha256' => { 'prior' => Digest::SHA256.file(old_path).hexdigest, 'replacements' => Digest::SHA256.file(new_path).hexdigest },
  'pricing_reference_sha256' => Digest::SHA256.file(File.join(output, 'pricing-reference.json')).hexdigest,
  'checker_sha256' => Digest::SHA256.file(__FILE__).hexdigest, 'verification' => 'passed' }
target = File.join(output, 'current-context-review.json')
raise 'Context binding exists' if File.exist?(target)
File.write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, output)
puts JSON.pretty_generate(report)
