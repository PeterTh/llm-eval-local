# frozen_string_literal: true
$stdout.sync = true
require_relative 'observer-pipeline-v3/tools/timing_audit/lib/timing_audit'
campaign = '/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra/evaluation'
primary = '/home/petert/llm_timing_audit/20261106-terra61-ultra-codex'
boundary = primary + '-qtclustering'
output = primary + '-cross-review-sol61'
id = 'qtclustering_gpt-6.1-terra-ultra_hybrid_r5'
report_path = File.join(campaign, 'audit-completion-review.json')
archived_report = File.join(campaign, 'audit-completion-before-cross-review.json')
raise 'Overlap reconciliation already exists' if File.exist?(output) || File.exist?(archived_report)
report = JSON.parse(File.read(report_path))
raise 'Unexpected overlap changes' unless report.fetch('overlay_verdict_changes').map { |row| row.fetch('program_id') } == [id]
inputs = [File.join(primary + '-sol61', 'results', id + '.json'), File.join(boundary, 'results', id + '.json')]
reviews = inputs.map { |path| JSON.parse(File.read(path)) }
raise 'Disagreement disappeared' unless reviews.map { |row| row.fetch('verdict') } == %w[invalid valid]
inventories = [primary + '-sol61', boundary].map do |root|
  TimingAudit.load_jsonl(File.join(root, 'inventory.jsonl')).find { |row| row.fetch('id') == id }
end
raise 'Different sources' unless inventories.all? && inventories.map { |row| row.fetch('source_digest') }.uniq.size == 1
parent = primary + '-sol61'
TimingAudit.derive_inventory(parent_root: parent, output_dir: output, ids: [id], provenance: {
  'cross_review_reconciliation' => { 'model' => 'gpt-6.1-sol', 'effort' => 'xhigh', 'blind' => false,
    'reason' => 'General timing and QT boundary verdict disagreement on the same source',
    'input_sha256' => inputs.to_h { |path| [path, TimingAudit.sha256_file(path)] } }
})
manifest_path = File.join(output, 'manifest.yaml')
manifest = YAML.safe_load_file(manifest_path)
(manifest['retained_artifacts'] || {}).each_key do |name|
  next if File.file?(File.join(output, name))
  TimingAudit.atomic_write(File.join(output, name), File.binread(File.join(parent, name)))
end
context = <<~TEXT

  TARGETED CROSS-REVIEW RECONCILIATION

  Two source-only reviews disagree on this same program. The unchanged timing
  contract above remains authoritative. Review the source and both arguments
  independently of reviewer labels. Do not resolve the case merely by majority
  vote or by mechanically requiring MPI_MAX. Conversely, a cooperative algorithm
  is not an independent complete-result replica just because every rank stores
  the result. Explain whether any work after the last collective is required to
  produce the one complete result, or is only redundant result assembly/cleanup;
  and whether the root interval proves the existing contract. Reconcile this
  particular disagreement in notes, with source-grounded evidence. If the
  existing contract and evidence do not settle it, return ambiguous rather than
  inventing a new policy. No source changes or executions are permitted.

  Prior review A (general timing):
  #{JSON.pretty_generate(reviews[0])}

  Prior review B (QT boundary):
  #{JSON.pretty_generate(reviews[1])}
TEXT
prompt_path = File.join(output, 'prompt-template.txt')
TimingAudit.atomic_write(prompt_path, File.binread(prompt_path) + context.gsub('%', '%%'))
manifest.fetch('artifacts')['prompt_template_sha256'] = TimingAudit.sha256_file(prompt_path)
if manifest['retained_artifacts']
  manifest.fetch('retained_artifacts').keys.each do |name|
    manifest['retained_artifacts'][name] = TimingAudit.sha256_file(File.join(output, name))
  end
end
TimingAudit.atomic_write(manifest_path, YAML.dump(manifest))
inputs.each_with_index { |path, index| TimingAudit.atomic_write(File.join(output, "input-review-#{index + 1}.json"), File.binread(path)) }
FileUtils.mv(report_path, archived_report)
FileUtils.cp(__FILE__, campaign)
TimingAudit::AuditRunner.new(output_dir: output, scope: 'full', jobs: 1,
  model: 'gpt-6.1-sol', effort: 'xhigh').run
puts 'Cross-review reconciliation complete; original reports and sources unchanged.'
