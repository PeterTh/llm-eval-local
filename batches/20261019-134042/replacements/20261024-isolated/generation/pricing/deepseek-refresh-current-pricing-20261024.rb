# frozen_string_literal: true
require 'json'
require 'net/http'
require 'digest'
require 'fileutils'
require 'time'

campaign = '/home/petert/llm_para_campaigns/20261019-134042-deepseek41-flash-opencode-high'
evidence = File.join(campaign, 'amendments/20261023-filesystem-isolation/evaluation')
output = File.join(evidence, 'pricing')
target = File.join(output, 'pricing-reference.json')
previous = JSON.parse(File.read(File.join(campaign, 'pricing/pricing-reference.json')))
raise 'Current pricing already recorded' if File.file?(File.join(output, 'pricing-refresh.json'))
records = Dir[File.join(campaign, 'observations/*.json')].sort.map { |p| JSON.parse(File.read(p)) }
complete = records.select { |r| r.fetch('usage_complete') }
raise 'Wrong current pricing scope' unless records.size == 220 && complete.size == 217
means = %w[input_tokens cached_input_tokens output_tokens].to_h { |k| [k, complete.sum { |r| r.fetch('token_counts').fetch(k) }.fdiv(complete.size)] }
endpoint = 'https://openrouter.ai/api/v1/models/deepseek/deepseek-v4.1-flash/endpoints'
response = Net::HTTP.get_response(URI(endpoint))
raise 'Public pricing request failed' unless response.is_a?(Net::HTTPSuccess)
data = JSON.parse(response.body).fetch('data')
raise 'Wrong model response' unless data.fetch('id') == 'deepseek/deepseek-v4.1-flash'
candidates = data.fetch('endpoints').map do |r|
  p = r.fetch('pricing')
  rates = { 'input' => Float(p.fetch('prompt')) * 1_000_000,
    'cached_input' => Float(p.fetch('input_cache_read', p.fetch('prompt'))) * 1_000_000,
    'output' => Float(p.fetch('completion')) * 1_000_000 }
  raise 'Invalid rates' unless rates.values.all? { |v| v.finite? && v >= 0 }
  cost = ((means.fetch('input_tokens') - means.fetch('cached_input_tokens')) * rates.fetch('input') +
    means.fetch('cached_input_tokens') * rates.fetch('cached_input') + means.fetch('output_tokens') * rates.fetch('output')) / 1_000_000
  r.slice('name', 'provider_name', 'tag', 'status', 'quantization', 'context_length', 'max_completion_tokens', 'pricing')
    .merge('rates_per_million' => rates, 'estimated_mean_cost_usd' => cost, 'eligible' => r.fetch('status') == 0 && !r.fetch('tag').include?('batch'))
end
ranked = candidates.select { |r| r.fetch('eligible') }.sort_by { |r| [r.fetch('estimated_mean_cost_usd'), r.fetch('tag')] }
raise 'No pricing candidate' if ranked.empty?
report = previous.except('native_context_sha256').merge(
  'checked_at' => Time.now.utc.iso8601, 'endpoint_response_sha256' => Digest::SHA256.hexdigest(response.body),
  'complete_observation_mean_tokens' => means, 'selected' => ranked.first, 'candidates' => candidates,
  'context_inputs' => {
    'prior_220_context_sha256' => Digest::SHA256.file(File.join(campaign, 'pricing/request-context-summary.json')).hexdigest,
    'replacement_24_context_sha256' => Digest::SHA256.file(File.join(output, 'request-context-summary.json')).hexdigest,
    'replacement_ids_sha256' => Digest::SHA256.file(File.join(File.dirname(evidence), 'run-ids.txt')).hexdigest,
    'selection' => 'Replace precisely these 24 IDs in the prior 220-record context; preserve the remaining 196.'
  }, 'checker_sha256' => Digest::SHA256.file(__FILE__).hexdigest)
File.write(target, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, output)
receipt = { 'checked_at' => report.fetch('checked_at'), 'pricing_reference_sha256' => Digest::SHA256.file(target).hexdigest,
  'selected' => ranked.first, 'complete_programs' => 217, 'incomplete_programs' => 3 }
File.write(File.join(output, 'pricing-refresh.json'), JSON.pretty_generate(receipt) + "\n")
puts JSON.pretty_generate(receipt)
