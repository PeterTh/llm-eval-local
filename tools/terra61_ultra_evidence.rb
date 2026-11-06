# frozen_string_literal: true
require_relative 'artifact_common'
require_relative '../method/codex-usage/codex_tree_usage'

module Terra61UltraEvidence
  module_function

  def verify_usage!(completion:, usage:, pricing:)
    records = usage.values
    records.each { |record| CodexTreeUsage.validate_record!(record) }
    uncertain = records.select { |record| record.fetch('interrupted_request_usage_uncertain') }.map { |r| r.fetch('run_id') }.sort
    totals = CodexTreeUsage.sum(records.map { |record| record.fetch('usage') })
    unless records.size == completion.fetch('usage_records') && totals == completion.fetch('recorded_usage') &&
        totals == pricing.fetch('total_usage') && records.sum { |r| r.fetch('sessions').size } == completion.fetch('sessions') &&
        completion.fetch('sessions') == pricing.fetch('sessions') &&
        records.sum { |r| r.fetch('request_count') } == completion.fetch('request_records') &&
        completion.fetch('request_records') == pricing.fetch('requests') &&
        uncertain.size == completion.fetch('interrupted_request_usage_uncertain_count') &&
        uncertain == pricing.fetch('interrupted_request_usage_uncertain_ids').sort &&
        pricing.fetch('accounting_scope') == 'parent_and_descendants' &&
        pricing.fetch('complete_billing_coverage_claimed') == false && completion.fetch('cleanup_verified') == true
      raise 'Recorded native tree usage reconciliation differs'
    end
    runs = pricing.fetch('runs')
    raise 'Request pricing identity differs' unless runs.map { |r| r.fetch('run_id') }.sort == usage.keys.sort
    runs.each do |run|
      record = usage.fetch(run.fetch('run_id'))
      unless run.fetch('requests') == record.fetch('request_count') && run.fetch('sessions') == record.fetch('sessions').size &&
          run.fetch('interrupted_request_usage_uncertain') == record.fetch('interrupted_request_usage_uncertain')
        raise 'Per-run native request accounting differs'
      end
    end
  end

  # Whitelisted compact receipts, never native chats, generated sources, builds,
  # executables or repeated complete method trees. Method bytes are deduplicated
  # against already retained artifact files by SHA-256.
  def retain(campaign:, copy:, selected:, json:, reusable:, batch_id:, pricing_report:)
    selected.call(campaign, 'generation', %w[original-source-push.json pilot-launch.json
      pilot-request-identity-and-shutdown.json pilot-session-inspection.json ultra-features.json
      preflight-usage.jsonl regression-tests.json tooling-commit.json])
    selected.call(File.join(campaign, 'full-campaign-20261105'), 'generation/full-campaign',
      %w[accounting-pilot-check.json campaign.before-full.json preparation.json launch.json
         check-accounting.rb finish-preparation.rb full-controller.rb launch-full.rb prepare-full.rb run-tests.rb regression-tests.json])
    repair = File.join(campaign, 'catalog-repair-20261105')
    selected.call(repair, 'generation/catalog-repair', %w[repair.json completed-review.json catalog-baseline-comparison.json
      filesystem-preflight.json request-identity-and-shutdown.json session-inspection.json retry-launch.json
      tooling-commit.json campaign.before-repair.json preflight-review.before-repair.json
      prepare-retry.rb review-retry.rb retry-controller.rb run.rb regression-tests.json])
    selected.call(File.join(repair, 'superseded/observations'), 'generation/catalog-repair/superseded/observations',
      ['matmul_gpt-6.1-terra-ultra_cuda_r1.json'])
    selected.call(File.join(repair, 'superseded/cleanup'), 'generation/catalog-repair/superseded/cleanup',
      ['matmul_gpt-6.1-terra-ultra_cuda_r1.json'])
    selected.call(File.join(repair, 'superseded/matmul_gpt-6.1-terra-ultra_cuda_r1'),
      'generation/catalog-repair/superseded/process', %w[timing.txt process-status.txt codex-filesystem.txt])
    retain_method_revisions(campaign: campaign, copy: copy, json: json, reusable: reusable, batch_id: batch_id)
    # The provider model metadata is reproducibility evidence, not an executable.
    Dir[File.join(repair, 'catalog-captures', '*')].sort.each do |path|
      next unless File.file?(path) && %w[.json .txt].include?(File.extname(path))
      raise 'Unexpected large model-catalog capture' if File.size(path) > 2_000_000
      copy.call(path, "generation/catalog-repair/catalog-captures/#{File.basename(path)}")
    end
    pricing = File.join(campaign, 'pricing')
    selected.call(pricing, 'generation/pricing', %w[audit-ultra-pricing.rb request-usage-tests.log model.md pricing.md])
    method_layout = pricing_report.fetch('method_sha256').to_h do |name, digest|
      raise 'Unsafe pricing method path' if Pathname.new(name).absolute? || name.split('/').include?('..')
      source = File.join(pricing, 'method', name)
      raise 'Pricing method differs' unless LocalEvalArtifact.sha256(source) == digest
      relative = reusable[digest]
      unless relative
        stored = "generation/pricing/method/#{name}"
        copy.call(source, stored)
        relative = "batches/#{batch_id}/#{stored}"
        reusable[digest] = relative
      end
      [name, relative]
    end
    json.call('generation/pricing/method-layout.json', method_layout)
    retain_observer_history(campaign: campaign, copy: copy, selected: selected, json: json,
      reusable: reusable, batch_id: batch_id)
  end

  def retain_method_revisions(campaign:, copy:, json:, reusable:, batch_id:)
    current = JSON.parse(File.read(File.join(campaign, 'campaign.json')))
    histories = [
      ['pilot', 'catalog-repair-20261105/campaign.before-repair.json', 'method',
       'generation/catalog-repair/campaign.before-repair.json'],
      ['catalog-repair', 'full-campaign-20261105/campaign.before-full.json', 'catalog-repair-20261105/method',
       'generation/full-campaign/campaign.before-full.json']
    ]
    revisions = histories.map.with_index do |(label, manifest_name, method_name, retained_manifest), index|
      manifest = JSON.parse(File.read(File.join(campaign, manifest_name)))
      declared = current.fetch('method_revisions').fetch(index)
      raise 'Historical generation revision differs' unless manifest.fetch('source_commit') == declared.fetch('commit')
      layout = manifest.fetch('files').to_h do |name, digest|
        raise 'Unsafe historical method path' if Pathname.new(name).absolute? || name.split('/').include?('..')
        source = File.join(campaign, method_name, name)
        raise 'Historical generation method differs' unless LocalEvalArtifact.sha256(source) == digest
        relative = reusable[digest]
        unless relative
          stored = "generation/#{label}-method/#{name.gsub('/bin/', '/commands/')}"
          copy.call(source, stored)
          relative = "batches/#{batch_id}/#{stored}"
          reusable[digest] = relative
        end
        [name, relative]
      end
      { 'label' => label, 'source_commit' => manifest.fetch('source_commit'),
        'manifest' => retained_manifest, 'manifest_sha256' => LocalEvalArtifact.sha256(File.join(campaign, manifest_name)),
        'files' => layout }
    end
    json.call('generation/method-revisions.json', revisions)
  end

  def retain_observer_history(campaign:, copy:, selected:, json:, reusable:, batch_id:)
    evaluation = File.join(campaign, 'evaluation')
    %w[observer-resume stencil-observer-resume].each do |name|
      source = File.join(evaluation, name)
      destination = "validation/observer-history/#{name}"
      resume = JSON.parse(File.read(File.join(source, 'resume.json')))
      selected.call(source, destination, %w[resume.json launch.json checks.json initial-campaign.json
        initial-validation-progress.json initial-validation-driver.rb initial-local-evaluation-driver.rb])
      initial = resume.fetch('initial_run')
      manifest = File.join(initial, 'evaluation_manifest.yaml')
      raise 'Observer origin manifest differs' unless LocalEvalArtifact.sha256(manifest) == resume.dig('initial_validation_review', 'manifest_sha256')
      copy.call(manifest, "#{destination}/origin-manifest.yaml")
      layout = resume.fetch('initial_pipeline').fetch('files').to_h do |relative, digest|
        raise 'Unsafe observer method path' if Pathname.new(relative).absolute? || relative.split('/').include?('..')
        file = File.join(resume.fetch('initial_pipeline').fetch('root'), relative)
        raise 'Original observer method differs' unless LocalEvalArtifact.sha256(file) == digest
        stored = reusable[digest]
        unless stored
          target = "#{destination}/method/#{relative}"
          copy.call(file, target)
          stored = "batches/#{batch_id}/#{target}"
          reusable[digest] = stored
        end
        [relative, stored]
      end
      json.call("#{destination}/method-layout.json", layout)
      imported = resume.fetch('imported_complete_records').map do |record|
        id = record.fetch('id')
        raise 'Unsafe observer import ID' unless id.match?(/\A[A-Za-z0-9_.-]+\z/)
        file = File.join(initial, 'validation', id, 'validation_metadata.yaml')
        digest = record.fetch('original_artifacts_sha256').fetch('validation_metadata.yaml')
        raise 'Original imported metadata differs' unless LocalEvalArtifact.sha256(file) == digest
        target = "#{destination}/origin-metadata/#{id}.yaml"
        copy.call(file, target)
        { 'id' => id, 'original_metadata' => target, 'sha256' => digest,
          'rebound_metadata_sha256' => record.fetch('rebound_metadata_sha256') }
      end
      json.call("#{destination}/imports.json", imported)
      pilot = File.join(source, 'pilot-full-array')
      receipt = JSON.parse(File.read(File.join(pilot, 'receipt.json')))
      raise 'Observer pilot failed' unless receipt.fetch('passed') && receipt.fetch('program_source_changes').zero?
      receipt.fetch('files_sha256').each do |relative, digest|
        raise 'Unsafe observer receipt member' unless %w[actual.json comparison.json reference.json].include?(relative)
        file = File.join(pilot, relative)
        raise 'Observer pilot evidence differs' unless LocalEvalArtifact.sha256(file) == digest
        copy.call(file, "#{destination}/pilot-full-array/#{relative}")
      end
      copy.call(File.join(pilot, 'receipt.json'), "#{destination}/pilot-full-array/receipt.json")
    end
  end
end
