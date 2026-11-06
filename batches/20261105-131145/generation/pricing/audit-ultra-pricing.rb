# frozen_string_literal: true
require '/home/petert/llm_eval/experiment/lib/codex_tree_requests'
require '/home/petert/llm_eval/experiment/lib/local_evaluation'
require 'bigdecimal'

root = '/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra'
pricing = File.join(root, 'pricing')
raise 'Generation incomplete' unless JSON.parse(File.read(File.join(root, 'progress.json'))).fetch('status') == 'complete'
pids, status = Open3.capture2('pgrep', '-u', 'llmtest')
raise 'Evaluation account active' unless status.exitstatus == 1 && pids.empty?
host_lock = LocalEvaluation::HostPerformanceLock.new
begin
  reference_path = File.join(pricing, 'pricing-reference.json')
  reference = JSON.parse(File.read(reference_path))
  raise 'Wrong pricing reference' unless reference.fetch('profile') == 'gpt-6.1-terra-ultra' &&
    reference.dig('selected', 'tag') == 'openai/flex' && reference.fetch('context_threshold_input_tokens') == 272000
  usage_path = File.join(root, 'codex-usage.jsonl')
  records = CodexUsage.load_records(usage_path)
  raise 'Wrong recorded scope' unless records.size == 220 && records.values.all? { |record|
    record.values_at('batch', 'model', 'reasoning_effort', 'accounting_scope') ==
      ['20261105-131145', 'gpt-6.1-terra', 'ultra', CodexTreeUsage::SCOPE] }
  output_path = File.join(pricing, 'codex-request-usage.jsonl')
  report_path = File.join(pricing, 'request-pricing-audit.json')
  raise 'Pricing audit already exists' if File.exist?(output_path) || File.exist?(report_path)
  repository = '/home/petert/llm_eval/experiment'
  method_names = %w[lib/codex_usage.rb lib/codex_tree_usage.rb lib/codex_tree_requests.rb tools/metadata/recover_codex_tree_requests.rb test/test_codex_tree_requests.rb]
  public_root = Dir.mktmpdir('terra-ultra-request-reader-', '/tmp')
  File.chmod(0o755, public_root)
  method = method_names.to_h do |relative|
    source = File.join(repository, relative)
    bytes = File.binread(source)
    target = File.join(public_root, relative)
    FileUtils.mkdir_p(File.dirname(target), mode: 0o755)
    File.binwrite(target, bytes)
    File.chmod(0o644, target)
    [relative, Digest::SHA256.hexdigest(bytes)]
  end
  test_output, test_error, test_status = Open3.capture3('/usr/bin/ruby',
    File.join(public_root, 'test/test_codex_tree_requests.rb'), '--seed', '20261106')
  raise "Request-reader regression failed: #{test_output} #{test_error}" unless test_status.success? &&
    test_output.include?('6 runs, 14 assertions, 0 failures, 0 errors, 0 skips')
  helper = File.join(public_root, 'tools/metadata/recover_codex_tree_requests.rb')
  output, error, status = Open3.capture3('su', '-', 'llmtest', '--shell=/bin/bash', '-c',
    Shellwords.join(['/usr/bin/ruby', helper, '--sessions=/home/llmtest/.codex/sessions']),
    stdin_data: JSON.generate(records.values))
  raise "Bound tree request recovery failed: #{error}" unless status.success?
  rows = output.lines.map { |line| JSON.parse(line) }
  raise 'Recovered scope changed' unless rows.map { |row| row.fetch('run_id') } == records.keys
  rows.each do |row|
    original = records.fetch(row.fetch('run_id'))
    raise 'Request evidence differs from retained generation accounting' unless
      row.fetch('final_record_sha256') == Digest::SHA256.hexdigest(JSON.generate(original)) &&
      row.fetch('total_usage') == original.fetch('usage') && row.fetch('request_count') == original.fetch('request_count') &&
      row.fetch('interrupted_request_usage_uncertain') == original.fetch('interrupted_request_usage_uncertain') &&
      row.fetch('sessions').map { |session| session.slice('session_id', 'session_path', 'session_sha256', 'session_bytes') } ==
        original.fetch('sessions').map { |session| session.slice('session_id', 'session_path', 'session_sha256', 'session_bytes') }
  end
  threshold = reference.fetch('context_threshold_input_tokens')
  rates = %w[short long].to_h { |band| [band, reference.fetch(band + '_rates_usd_per_million')
    .transform_values { |value| BigDecimal(value.to_s) / 1_000_000 }] }
  totals = CodexTreeUsage.zero
  bands = %w[short long].to_h { |band| [band, { 'requests' => 0, 'input_tokens' => 0, 'cached_input_tokens' => 0, 'output_tokens' => 0 }] }
  total_cost = BigDecimal('0')
  run_costs = rows.map do |row|
    cost = BigDecimal('0')
    row.fetch('requests').each do |request|
      usage = request.fetch('usage')
      raise 'Cache-write usage needs explicit pricing' unless usage.fetch('cache_write_input_tokens').zero?
      band = usage.fetch('input_tokens') > threshold ? 'long' : 'short'
      selected = rates.fetch(band)
      bands.fetch(band)['requests'] += 1
      %w[input_tokens cached_input_tokens output_tokens].each { |field| bands.fetch(band)[field] += usage.fetch(field) }
      totals.each_key { |field| totals[field] += usage.fetch(field) }
      cost += (usage.fetch('input_tokens') - usage.fetch('cached_input_tokens')) * selected.fetch('prompt') +
        usage.fetch('cached_input_tokens') * selected.fetch('input_cache_read') + usage.fetch('output_tokens') * selected.fetch('completion')
    end
    total_cost += cost
    { 'run_id' => row.fetch('run_id'), 'requests' => row.fetch('request_count'), 'sessions' => row.fetch('sessions').size,
      'max_request_input_tokens' => row.fetch('max_request_input_tokens'), 'api_equivalent_cost_usd' => cost.to_s('F'),
      'interrupted_request_usage_uncertain' => row.fetch('interrupted_request_usage_uncertain') }
  end
  raise 'Aggregate request totals differ' unless totals == CodexTreeUsage.sum(records.values.map { |record| record.fetch('usage') })
  uncertain = rows.select { |row| row.fetch('interrupted_request_usage_uncertain') }.map { |row| row.fetch('run_id') }
  report = { 'schema_version' => 2, 'checked_at' => Time.now.utc.iso8601, 'profile' => reference.fetch('profile'),
    'source' => 'Recorded native requests across bound parent and descendant sessions; unique request IDs and every cumulative/count-stream record verified against retained whole-tree totals.',
    'accounting_scope' => CodexTreeUsage::SCOPE, 'generation_complete_before_session_inspection' => true,
    'native_workloads_idle_during_session_inspection' => true, 'observations' => rows.size,
    'sessions' => rows.sum { |row| row.fetch('sessions').size }, 'requests' => rows.sum { |row| row.fetch('request_count') },
    'duplicate_native_records_ignored' => 0, 'token_count_snapshots_verified' => rows.sum { |row| row.fetch('token_count_snapshots_verified') },
    'max_request_input_tokens' => rows.map { |row| row.fetch('max_request_input_tokens') }.max,
    'context_threshold_input_tokens' => threshold, 'long_context_rule' => 'input_tokens > 272000; full-request rates',
    'by_context_tier' => bands, 'total_usage' => totals, 'cache_write_input_tokens_known_zero' => true,
    'pricing_as_of' => reference.fetch('pricing_as_of'), 'selected_endpoint' => reference.fetch('selected').slice('name', 'tag', 'service_tier'),
    'total_api_equivalent_cost_usd' => total_cost.to_s('F'), 'mean_api_equivalent_cost_usd' => (total_cost / rows.size).to_s('F'),
    'interrupted_request_usage_uncertain_ids' => uncertain, 'complete_billing_coverage_claimed' => uncertain.empty?,
    'interruption_policy' => 'Prices apply to recorded counters only. Interrupted requests may have unrecorded usage; do not assume that missing usage is zero. Scientific observations are retained.',
    'pricing_reference_sha256' => Digest::SHA256.file(reference_path).hexdigest,
    'final_usage_sha256' => Digest::SHA256.file(usage_path).hexdigest,
    'request_usage_sha256' => Digest::SHA256.hexdigest(output), 'request_usage_bytes' => output.bytesize,
    'reader_sha256' => method.fetch('lib/codex_tree_requests.rb'), 'method_sha256' => method,
    'tests' => { 'runs' => 6, 'assertions' => 14, 'failures' => 0, 'errors' => 0, 'seed' => 20261106 },
    'driver_sha256' => Digest::SHA256.file(__FILE__).hexdigest,
    'scope' => 'Ultra only; model-frozen rates, historical prices and measurements unchanged. API-equivalent comparison, not subscription billing.',
    'runs' => run_costs }
  method.each_key do |relative|
    target = File.join(pricing, 'method', relative)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(File.join(public_root, relative), target)
  end
  FileUtils.cp(__FILE__, pricing)
  LocalEvaluation.atomic_write(File.join(pricing, 'request-usage-tests.log'), test_output + test_error)
  LocalEvaluation.atomic_write(output_path, output)
  LocalEvaluation.atomic_write(report_path, JSON.pretty_generate(report) + "\n")
  puts JSON.pretty_generate(report.reject { |key, _| %w[runs interrupted_request_usage_uncertain_ids method_sha256].include?(key) })
ensure
  host_lock.close
end
