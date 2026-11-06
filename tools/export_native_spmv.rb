# frozen_string_literal: true
require_relative 'artifact_common'
require 'open3'

module NativeSpmvExport
  module_function

  def verify_completion!(completion, current)
    raise 'Native SpMV review incomplete' unless completion.fetch('status') == 'complete' &&
      completion.fetch('full_scope_accounted_for') && completion.fetch('evidence_verified') &&
      completion.fetch('remaining').zero? && completion.fetch('new_failures').empty? &&
      %w[program_executions compilation benchmark_runs program_changes].all? { |key| completion.fetch(key) == 0 }
    %w[population reused_pilot_reviews new_reviews remaining review_sha256].each do |key|
      raise "Native SpMV completion differs: #{key}" unless completion.fetch(key) == current.fetch(key)
    end
    raise 'Native SpMV evidence not verified' unless current.fetch('evidence_verified')
  end

  def run(method_root:, workspace:, evidence:, destination:)
    require File.join(method_root, 'tools/validation_audit/spmv_native_review')
    require File.join(method_root, 'tools/validation_audit/export_spmv_full')
    reviewer = ValidationAudit::SpmvNativeReview.new(workspace: workspace, evidence: evidence)
    completion_path = File.join(reviewer.root, 'completion.json')
    completion = ValidationAudit.read(completion_path)
    verify_completion!(completion, reviewer.verify)
    sources = {
      'completion.json' => completion_path,
      'authorization.json' => File.join(reviewer.root, 'authorization.json'),
      'pilot-quality-check.json' => File.join(reviewer.root, 'pilot-quality-check.json'),
      'native-spmv-inventory.json' => File.join(evidence, 'native-spmv-inventory.json')
    }
    { 'inventory_sha256' => 'native-spmv-inventory.json', 'authorization_sha256' => 'authorization.json' }.each do |key, name|
      raise 'Native SpMV scope changed' unless completion.fetch(key) == LocalEvalArtifact.sha256(sources.fetch(name))
    end
    completion.fetch('review_sha256').each do |id, digest|
      raise 'Unsafe native SpMV ID' unless id.match?(/\Aspmv_[A-Za-z0-9_.-]+\z/)
      path = File.join(reviewer.root, 'reviews', id + '.json')
      raise 'Native SpMV review changed' unless LocalEvalArtifact.sha256(path) == digest
      row = JSON.parse(File.read(path))
      sources["reviews/#{id}.json"] = path
      sources["packs/#{id}.json"] = File.join(reviewer.root, 'packs', id + '.json')
      sources["bindings/#{id}.json"] = File.join(evidence, 'bindings', id + '.json')
      input = row.fetch('review_input_sha256')
      raise 'Unsafe native SpMV input' unless input.match?(/\A[0-9a-f]{64}\z/)
      sources["review-inputs/#{input}.json"] = File.join(reviewer.root, 'review-inputs', input + '.json')
    end
    Dir[File.join(reviewer.root, 'delegated-proposals/*.json')].sort.each do |path|
      sources["delegated-proposals/#{File.basename(path)}"] = path
    end
    names = %w[tools/validation_audit/spmv_native_review.rb tools/validation_audit/spmv_full_review.rb
      tools/validation_audit/spmv_work_count.rb tools/validation_audit/export_spmv_full.rb]
    commit, error, status = Open3.capture3('git', '-C', method_root, 'rev-parse', 'HEAD')
    raise "Cannot bind native SpMV method: #{error}" unless status.success? && commit.strip.match?(/\A[0-9a-f]{40}\z/)
    method = { 'repository' => 'https://github.com/PeterTh/llm-eval-experiment',
      'commit' => commit.strip,
      'files_sha256' => names.to_h { |name| [name, LocalEvalArtifact.sha256(File.join(method_root, name))] },
      'exporter_sha256' => LocalEvalArtifact.sha256(__FILE__) }
    ValidationAudit::SpmvFullExport.write_bundle(destination: destination, sources: sources,
      summary: completion.reject { |key, _| key == 'review_sha256' }.merge(
        'retention' => 'Accepted inputs, exact review excerpts, source/executable bindings, pilot checks and proposals. No binaries, complete disassembly, generated-source copies, executions or recompilations.'), method: method)
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: export_native_spmv.rb METHOD_ROOT WORKSPACE EVIDENCE NEW_DESTINATION' unless ARGV.size == 4
  result = NativeSpmvExport.run(method_root: ARGV[0], workspace: ARGV[1], evidence: ARGV[2], destination: ARGV[3])
  puts JSON.pretty_generate(result.reject { |key, _| key == 'files_sha256' })
end
