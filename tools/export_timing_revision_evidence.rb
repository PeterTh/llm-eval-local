# frozen_string_literal: true

require_relative 'artifact_common'

# Supplements the native final-correction export with only superseded evidence.
# Unchanged proposals/reviews remain stored once in the native stage export.
module TimingRevisionEvidenceExport
  module_function

  def collect(gate_path)
    gate = JSON.parse(File.read(gate_path))
    raise 'Revision not accepted' unless gate.fetch('passed') && gate.fetch('prior_evidence_unchanged')
    id = gate.fetch('program_id')
    raise 'Unsafe program ID' unless id.match?(/\A[a-zA-Z0-9_.-]+\z/)
    previous = gate.fetch('prior_roots')
    current = gate.fetch('evidence_roots')
    pending = {}
    retain = lambda do |source, relative|
      raise 'Unsafe evidence path' if Pathname.new(relative).absolute? || relative.split('/').any? { |part| %w[. ..].include?(part) }
      raise 'Symlink evidence' if File.symlink?(source)
      pending[relative] = File.binread(source)
    end
    old_ids = LocalEvalArtifact.read_jsonl(File.join(previous.fetch('proposals'), 'inventory.jsonl')).map { |row| row.fetch('id') }.sort
    new_ids = LocalEvalArtifact.read_jsonl(File.join(current.fetch('proposals'), 'inventory.jsonl')).map { |row| row.fetch('id') }.sort
    raise 'Revision coverage changed' unless old_ids == new_ids && new_ids == new_ids.uniq && new_ids.include?(id) && new_ids.size == gate.fetch('accepted_corrections')
    %w[proposals review adjudication].each do |stage|
      result_dir = stage == 'proposals' ? 'proposals' : 'results'
      old_results = Dir[File.join(previous.fetch(stage), result_dir, '*.json')].sort
      new_results = Dir[File.join(current.fetch(stage), result_dir, '*.json')].sort
      reused = []
      changed = []
      old_results.each do |path|
        basename = File.basename(path)
        replacement = File.join(current.fetch(stage), result_dir, basename)
        if File.file?(replacement) && LocalEvalArtifact.sha256(path) == LocalEvalArtifact.sha256(replacement)
          reused << basename.delete_suffix('.json')
        else
          changed << basename.delete_suffix('.json')
          retain.call(path, "#{stage}/superseded/#{basename}")
        end
      end
      if %w[proposals review].include?(stage)
        raise "Unexpected changed #{stage}" unless changed == [id] && reused.size == gate.fetch('unchanged_proposals') &&
          old_results.map { |path| File.basename(path) } == new_results.map { |path| File.basename(path) }
      end
      %w[manifest.yaml summary-full.jsonl environment-evidence.yaml].each do |name|
        path = File.join(previous.fetch(stage), name)
        retain.call(path, "#{stage}/#{name}") if File.file?(path)
      end
      if stage == 'proposals'
        retain.call(File.join(previous.fetch(stage), 'materialized/summary-full.yaml'), 'proposals/compile-summary.yaml')
      end
      # Native proposal export already includes every old and revised attempt.
      unless stage == 'proposals'
        retained_ids = stage == 'adjudication' ? old_results.map { |path| File.basename(path, '.json') } : changed
        attempts = retained_ids.flat_map do |key|
          Dir[File.join(previous.fetch(stage), 'logs', key, 'attempt-*/metadata.yaml')].sort.map { |path| LocalEvalArtifact.load_yaml(path) }
        end
        pending["#{stage}/superseded-attempts.jsonl"] = attempts.map { |row| JSON.generate(row) + "\n" }.join
      end
      inventory = LocalEvalArtifact.read_jsonl(File.join(previous.fetch(stage), 'inventory.jsonl'))
      selected_inventory = inventory.select { |row| changed.include?(row.fetch('id')) }
      pending["#{stage}/superseded-inventory.jsonl"] = selected_inventory.map { |row| JSON.generate(row) + "\n" }.join
      pending["#{stage}/reconstruction.json"] = JSON.pretty_generate({
        'unchanged_ids' => reused, 'superseded_ids' => changed,
        'original_inventory_order' => inventory.map { |row| row.fetch('id') },
        'recipe' => 'Start from the final native stage results and replace the listed superseded IDs. Inventory and snapshots follow original manifest ordering; unchanged source and response bytes are not duplicated.'
      }) + "\n"
    end
    bindings = {
      'prior_proposal_sha256' => File.join(previous.fetch('proposals'), 'proposals', "#{id}.json"),
      'prior_independent_review_sha256' => File.join(previous.fetch('review'), 'results', "#{id}.json"),
      'revised_proposal_sha256' => File.join(current.fetch('proposals'), 'proposals', "#{id}.json"),
      'accepted_review_sha256' => File.join(current.fetch('review'), 'results', "#{id}.json"),
      'reuse_receipt_sha256' => File.join(current.fetch('review'), 'reused-reviews.json')
    }
    bindings.each { |key, path| raise "Revision binding changed: #{key}" unless LocalEvalArtifact.sha256(path) == gate.fetch(key) }
    raise 'Operator scope receipt changed' unless LocalEvalArtifact.sha256(File.join(File.dirname(gate_path), 'correction-full-operator-scope-review.json')) == gate.fetch('operator_scope_review_sha256')
    retain.call(File.join(current.fetch('review'), 'reused-reviews.json'), 'reused-reviews.json')
    Dir[File.join(current.fetch('proposals'), 'revisions', '**', '*')].sort.each do |path|
      next unless File.file?(path)
      relative = path.delete_prefix(File.join(current.fetch('proposals'), 'revisions') + '/')
      raise 'Unexpected revision artifact' unless %w[.json .yaml .rb].include?(File.extname(path))
      retain.call(path, "requests/#{relative}")
    end
    evaluation = File.dirname(gate_path)
    %w[correction-revision-1.json correction-revision-feedback.json correction-revision-launch.json
      correction-revision-driver.rb reuse-unchanged-correction-reviews.rb launch-correction-revision.rb
      correction-full-operator-scope-review.json record-full-patch-scope-review.rb
      correction-revision-diff-check.json verify-correction-revision-scope.rb
      correction-followup-rebinding.json prepare-revised-correction-followup.rb
      cahn-hilliard-event-semantics-check.json].each do |name|
      retain.call(File.join(evaluation, name), "completion/#{name}")
    end
    pending
  end

  def run(batch_dir:, gate_path:)
    pending = collect(gate_path) # Verify everything before writing anything.
    destination = File.join(batch_dir, 'timing-corrections/revision-history')
    raise 'Revision history already exported' if File.exist?(destination)
    pending.each do |relative, bytes|
      path = File.join(destination, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
    end
    receipt = { 'schema_version' => 1, 'gate_sha256' => LocalEvalArtifact.sha256(gate_path),
      'files' => pending.size, 'bytes' => pending.values.sum(&:bytesize),
      'sha256' => pending.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) },
      'policy' => 'Superseded proposal and review evidence only; unchanged results and native attempt records are not duplicated. No binaries, builds or full event streams.' }
    File.write(File.join(destination, 'export.json'), JSON.pretty_generate(receipt) + "\n")
    receipt
  end
end
