# frozen_string_literal: true
require_relative 'experiment/tools/validation_audit/spmv_native_review'
require_relative 'audit-citation-normalization'
campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
evidence = File.join(campaign, 'spmv-review')
root = File.join(evidence, 'spmv-work-count-full')
audit = '/home/petert/llm_timing_audit/20261107-fable51-medium'
receipt_path = File.join(campaign, 'static-review-export-preparation.json')
raise 'Already prepared' if File.exist?(receipt_path)
completion = ValidationAudit.read(File.join(root, 'completion.json'))
raise 'SpMV incomplete' unless completion.fetch('status') == 'complete' && completion.fetch('population') == 20 && completion.fetch('new_failures').empty?
reviewer = ValidationAudit::SpmvNativeReview.new(workspace: '/tmp/fable51-spmv-review-20261107-4143246-6l4866', evidence: evidence)
verified = reviewer.verify
raise 'SpMV accepted evidence changed' unless verified.fetch('review_sha256') == completion.fetch('review_sha256')
copied = {}
copy = lambda do |source, target|
  raise "Missing evidence: #{source}" unless File.file?(source)
  raise "Destination exists: #{target}" if File.exist?(target)
  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.cp(source, target, preserve: true)
  digest = ValidationAudit.sha(source)
  raise 'Evidence copy changed' unless ValidationAudit.sha(target) == digest
  copied[target] = { 'source' => source, 'sha256' => digest, 'bytes' => File.size(target) }
end
copy.call(File.join(evidence, 'pilot-quality/quality-gate.json'), File.join(root, 'pilot-quality-check.json'))
%w[pilot mpi omp gpu].each do |group|
  directory = File.join(evidence, "#{group}-quality")
  files = Dir[File.join(directory, '*.json')].sort.reject { |path| File.basename(path) == 'accepted-review.json' }
  files.each do |source|
    copy.call(source, File.join(root, 'delegated-proposals', "#{group}-#{File.basename(source)}"))
  end
end
normalization_summary = ValidationAudit.read(File.join(campaign, 'audit-citation-normalization.json'))
normalization_path = normalization_summary.fetch('receipt')
raise 'Normalization receipt changed' unless ValidationAudit.sha(normalization_path) == normalization_summary.fetch('receipt_sha256')
AuditCitationNormalization.verify!(normalization_path)
normalization_dir = File.dirname(normalization_path)
recovery = File.join(audit, 'recovery')
raise 'Existing recovery requires merge review' if File.exist?(recovery)
Dir[File.join(normalization_dir, '*')].sort.select { |path| File.file?(path) }.each do |source|
  copy.call(source, File.join(recovery, 'qt-hybrid-r3-' + File.basename(source)))
end
id = 'qtclustering_claude-fable-5.1-cc-medium_hybrid_r3'
(1..4).each do |number|
  %w[events.jsonl metadata.yaml].each do |name|
    source = File.join(audit, 'logs', id, format('attempt-%02d', number), name)
    copy.call(source, File.join(recovery, format('qt-hybrid-r3-attempt-%02d-%s', number, name)))
  end
end
layout = copied.select { |target, _| target.start_with?(recovery + '/') }.to_h { |target, entry| [entry.fetch('source'), File.basename(target)] }
ValidationAudit.save(File.join(recovery, 'layout.json'), {
  'purpose' => 'Portable map for the exceptional syntax-only citation recovery; all other audit attempts use the usual compact export.',
  'original_absolute_path_to_retained_filename' => layout,
  'raw_model_responses_preserved' => true, 'scientific_findings_unchanged' => true,
  'normalization_verification' => 'Split the raw response citation list at comma separators; preserve exact individual ranges, source path and finding. The normalized response is also in primary/results.jsonl.',
  'no_new_model_invocation_for_normalization' => true
})
report = {
  'prepared_at' => Time.now.utc.iso8601,
  'spmv_completion_sha256' => ValidationAudit.sha(File.join(root, 'completion.json')),
  'normalization_receipt_sha256' => ValidationAudit.sha(normalization_path),
  'copied_files' => copied, 'copied_bytes' => copied.values.sum { |entry| entry.fetch('bytes') },
  'policy' => 'Use existing native SpMV exporter and flat timing-audit recovery export. Exact accepted inputs and compact excerpts remain; no executables, full disassembly, generated-source duplicates or extra program executions.',
  'public_package_exported' => false
}
ValidationAudit.save(receipt_path, report)
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report.reject { |key, _| key == 'copied_files' })
