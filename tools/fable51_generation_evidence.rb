# frozen_string_literal: true

require 'json'
require 'digest'
require 'pathname'

# Compact generation provenance for the resumed native-Claude campaign.
# No generated-source copies, credentials, build trees, or model invocations.
module Fable51GenerationEvidence
  BATCH = '20261011-092100'
  ORIGINAL = 'e3a476e84284ddea4052c6e55e92439f10f38b1a'
  PROFILE = 'claude-fable-5.1-cc-medium'
  module_function

  def safe_relative!(name)
    raise 'Unsafe evidence path' if name.empty? || Pathname.new(name).absolute? || name.split('/').any? { |part| %w[. ..].include?(part) }
    name
  end

  def sha(path)
    raise "Non-regular evidence: #{path}" unless File.file?(path) && !File.symlink?(path)
    Digest::SHA256.file(path).hexdigest
  end

  def verify_observations!(observations, rows, completion)
    raise 'Wrong original completion' unless completion.fetch('source_commit') == ORIGINAL &&
      completion.fetch('observations') == 220 && completion.fetch('accepted_generation_invocations') == 220 &&
      completion.fetch('outcomes') == { 'completed' => 220 }
    ids = observations.map { |row| row.fetch('id') }
    raise 'Generation scope differs' unless ids.size == 220 && ids.uniq.size == 220 && ids.sort == rows.keys.sort
    observations.each do |observation|
      id = observation.fetch('id')
      row = rows.fetch(id)
      raise "Wrong accepted observation: #{id}" unless observation.fetch('outcome') == 'completed' &&
        observation.fetch('model') == 'claude-fable-5-1' && observation.fetch('version') == '2.1.287' &&
        observation.fetch('retry_count').zero? && observation.fetch('retry_backoff_seconds').zero?
      counters = observation.fetch('token_counts')
      input = %w[input_tokens cache_creation_input_tokens cache_read_input_tokens].sum { |key| counters.fetch(key) }
      raise 'Inclusive usage differs' unless input == observation.fetch('inclusive_input_tokens') &&
        input + counters.fetch('output_tokens') == observation.fetch('total_tokens')
      { 'input_tokens' => input, 'output_tokens' => counters.fetch('output_tokens'),
        'cached_tokens' => counters.fetch('cache_read_input_tokens'), 'total_tokens' => observation.fetch('total_tokens'),
        'api_time' => observation.fetch('api_seconds'), 'total_time' => observation.fetch('total_seconds') }.each do |key, value|
        raise "Aggregate differs: #{id}/#{key}" unless Float(row.fetch(key)) == value
      end
    end
    raise 'Accepted sessions not unique' unless observations.map { |row| row.fetch('session_id') }.uniq.size == 220
    raise 'Token total differs' unless observations.sum { |row| row.fetch('total_tokens') } == completion.fetch('total_tokens')
    raise 'Duration total differs' unless (observations.sum { |row| row.fetch('total_seconds') } - completion.fetch('generation_seconds')).abs < 1e-6
    isolated = observations.count { |row| row.key?('filesystem_isolation') }
    raise 'Isolation tranche differs' unless isolated == completion.fetch('isolated_observations') &&
      observations.size - isolated == completion.fetch('pre_isolation_observations_preserved')
  end

  def retry_excerpts!(campaign, completion)
    path = File.join(campaign, 'generation.log')
    raise 'Generation log changed' unless File.size(path) == completion.fetch('generation_log_bytes') &&
      sha(path) == completion.fetch('generation_log_sha256')
    seen = []
    completion.fetch('provider_failed_attempts').map do |attempt|
      id = attempt.fetch('id')
      raise 'Duplicate provider retry' if seen.include?(id)
      seen << id
      observation_path = File.join(campaign, 'observations', id + '.json')
      raise 'Retry observation changed' unless sha(observation_path) == attempt.fetch('observation_sha256')
      observation = JSON.parse(File.read(observation_path))
      raise 'Accepted retry timing differs' unless observation.fetch('total_seconds') == attempt.fetch('accepted_attempt_seconds') &&
        observation.fetch('total_tokens') == attempt.fetch('accepted_total_tokens') && attempt.fetch('provider_status') == 429
      bytes = File.binread(path, attempt.fetch('excerpt_bytes'), attempt.fetch('excerpt_start_byte'))
      raise 'Retry excerpt changed' unless Digest::SHA256.hexdigest(bytes) == attempt.fetch('excerpt_sha256')
      [id, bytes]
    end
  end

  def retain(campaign:, root:, rows:, copy:, json:, jsonl:, write:)
    completion = JSON.parse(File.read(File.join(campaign, 'completion-audit.json')))
    observations = Dir[File.join(campaign, 'observations/*.json')].sort.map { |path| JSON.parse(File.read(path)) }
    verify_observations!(observations, rows, completion)
    cleanup = Dir[File.join(campaign, 'cleanup/*.json')].sort.map { |path| JSON.parse(File.read(path)) }
    raise 'Cleanup scope differs' unless cleanup.map { |row| row.fetch('id') }.sort == rows.keys.sort &&
      cleanup.all? { |row| row.fetch('verified_empty') }
    jsonl.call('generation/observations.jsonl', observations)
    jsonl.call('generation/cleanup.jsonl', cleanup)

    selected = lambda do |directory, names|
      names.each do |name|
        relative = safe_relative!([directory, name].reject(&:empty?).join('/'))
        source = File.join(campaign, relative)
        sha(source)
        copy.call(source, "generation/#{relative}")
      end
    end
    selected.call('', %w[campaign.json run-ids.txt preflight-ids.txt preflight-gate.json preflight-review.json
      claude-preflight.json completion.json completion-audit.json original-source-push.json source-retention-push.json
      launch.json operator-pause.json operator-pause-20261017.json
      prepare.rb run.rb monitor.rb inspect_claude.rb verify-preflight.rb audit-completion.rb])
    completion.fetch('provider_retry_receipt_sha256').each do |name, digest|
      raise 'Provider receipt changed' unless sha(File.join(campaign, safe_relative!(name))) == digest
      selected.call('', [name])
    end
    retry_excerpts!(campaign, completion).each do |id, bytes|
      write.call("generation/provider-retry-excerpts/#{id}.log", bytes)
    end
    selected.call('quota-resume-20261016', %w[amendment.json policy.patch quota-analysis.json launch.json first-acceptance.json])
    selected.call('legacy-notification-20261016', %w[amendment.json launch.json progress-at-stop.json])
    selected.call('filesystem-isolation-20261024', %w[amendment.json experiment-amendment.diff isolation-preflight.json
      isolation-preflight.log regression-tests.log initial-live-check.json cleanup-scope-fix.json cleanup-scope-fix.diff
      cleanup-fix-resume.json launch.json tranche-completion.json])
    %w[quota-resume-20261030 quota-resume-20261106].each do |directory|
      selected.call(directory, %w[prepared.json launch.json previous-state-retention.json])
    end
    selected.call('quota-resume-20261030', %w[auth-helper-path-recovery.json first-resumed-completion.json
      tranche-completion-20261031.json quota-pause-20261031.json])
    selected.call('quota-resume-20261106', %w[authentication-blocker.json template-reuse.json])

    # Reuse existing method blobs across batches; snapshots are retained once by
    # content, with explicit layouts for each actual campaign revision.
    reusable = {}
    LocalEvalArtifact.regular_files(root).each do |path|
      relative = LocalEvalArtifact.relative_path(root, path)
      next unless relative.start_with?('method/') || relative.match?(%r{\Abatches/[^/]+/(?:method|generation/(?:method|runtime-method)|timing-corrections/method|benchmark/method)/})
      reusable[sha(path)] ||= relative
    end
    retain_method = lambda do |label, files|
      layout = files.to_h do |name, (source, expected)|
        safe_relative!(name)
        digest = sha(source)
        raise "Changed method: #{source}" if expected && digest != expected
        stored = reusable[digest]
        unless stored
          relative = "generation/method/#{label}/#{name.gsub('/bin/', '/commands/')}"
          copy.call(source, relative)
          stored = "batches/#{BATCH}/#{relative}"
          reusable[digest] = stored
        end
        [name, { 'sha256' => digest, 'path' => stored }]
      end
      json.call("generation/method-layout-#{label}.json", layout)
      json.call('generation/method-layout.json', layout.transform_values { |binding| binding.fetch('path') }) if label == 'original'
    end
    manifest = JSON.parse(File.read(File.join(campaign, 'campaign.json')))
    raise 'Generation identity differs' unless manifest.fetch('campaign_id') == BATCH && manifest.fetch('model') == PROFILE &&
      manifest.fetch('reasoning_effort') == 'medium' && manifest.fetch('claude_version') == '2.1.287'
    retain_method.call('original', manifest.fetch('files').to_h { |name, digest| [name, [File.join(campaign, 'method', name), digest]] })
    %w[quota-resume-20261016 legacy-notification-20261016].each do |directory|
      amendment = JSON.parse(File.read(File.join(campaign, directory, 'amendment.json')))
      files = amendment.fetch('runtime_files').to_h do |name, digest|
        [name, [File.join(campaign, directory, 'runtime', safe_relative!(name)), digest]]
      end
      retain_method.call(directory, files)
    end
    isolation = 'filesystem-isolation-20261024'
    amendment = JSON.parse(File.read(File.join(campaign, isolation, 'cleanup-scope-fix.json')))
    working = amendment.fetch('working_directory') + '/'
    files = amendment.fetch('runtime_files').to_h do |original_path, digest|
      name = original_path.start_with?(working) ? original_path.delete_prefix(working) : File.basename(original_path)
      retained = File.join(campaign, isolation, 'method', name)
      retained = File.join(campaign, isolation, name) unless File.file?(retained)
      [name, [retained, digest]]
    end
    raise 'Runtime basename collision' unless files.size == amendment.fetch('runtime_files').size
    retain_method.call(isolation, files)

    pricing = File.join(campaign, 'pricing')
    price = JSON.parse(File.read(File.join(pricing, 'pricing-reference.json')))
    raise 'Pricing evidence differs' unless price.fetch('model') == 'anthropic/claude-fable-5.1' &&
      price.fetch('response_sha256') == sha(File.join(pricing, 'openrouter-endpoints.json'))
    selected.call('pricing', %w[pricing-reference.json openrouter-endpoints.json retain-pricing-preparation.rb])
    { 'records' => 220, 'exact_counters_verified' => 220,
      'provider_failed_attempts' => completion.fetch('provider_failed_attempts').size,
      'provider_retry_timing' => completion.fetch('provider_retry_timing'),
      'accepted_attempt_internal_retries' => 0, 'isolated_observations' => completion.fetch('isolated_observations'),
      'pre_isolation_observations_preserved' => completion.fetch('pre_isolation_observations_preserved'),
      'generation_seconds' => completion.fetch('generation_seconds'), 'total_tokens' => completion.fetch('total_tokens'),
      'pricing' => 'generation/pricing/pricing-reference.json' }
  end
end
