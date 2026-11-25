# frozen_string_literal: true
$stdout.sync = true
require_relative 'observer-pipeline-v5/tools/timing_audit/lib/timing_audit'
campaign = '/home/petert/llm_para_campaigns/20261123-155235-gpt62-astra-sol-medium/evaluation'
primary = '/home/petert/llm_timing_audit/20261125-gpt62-astra-sol-medium'
boundary = primary + '-qtclustering'
output = primary + '-cross-review-sol61'
id = 'qtclustering_gpt-6.2-sol-medium_hybrid_r3'
report_path = File.join(campaign, 'audit-completion-review.json')
archived_report = File.join(campaign, 'audit-completion-before-cross-review.json')
progress_path = File.join(campaign, 'timing-overlap-progress.json')
phase = 'prepare_same_source_reconciliation'
checkpoint = lambda do |extra = {}|
  TimingAudit.atomic_write(progress_path, JSON.pretty_generate({ 'updated_at' => TimingAudit.utc_now,
    'pid' => Process.pid, 'phase' => phase, 'driver_sha256' => TimingAudit.sha256_file(__FILE__) }.merge(extra)) + "\n")
end
begin
  checkpoint.call
  raise 'Reconciliation already exists' if File.exist?(output) || File.exist?(archived_report)
  report = JSON.parse(File.read(report_path))
  raise 'Unexpected overlap changes' unless report.fetch('overlay_verdict_changes').map { |row| row.fetch('program_id') } == [id] && report.fetch('unresolved').empty?
  inputs = [File.join(primary + '-sol61', 'results', id + '.json'), File.join(boundary, 'results', id + '.json')]
  reviews = inputs.map { |path| JSON.parse(File.read(path)) }
  raise 'Disagreement changed' unless reviews.map { |row| row.fetch('verdict') } == %w[valid invalid]
  inventories = [primary + '-sol61', boundary].map do |root|
    TimingAudit.load_jsonl(File.join(root, 'inventory.jsonl')).find { |row| row.fetch('id') == id }
  end
  raise 'Different sources' unless inventories.all? && inventories.map { |row| row.fetch('source_digest') }.uniq.size == 1
  parent = boundary
  TimingAudit.derive_inventory(parent_root: parent, output_dir: output, ids: [id], provenance: {
    'cross_review_reconciliation' => { 'model' => 'gpt-6.1-sol', 'effort' => 'xhigh', 'blind' => false,
      'reason' => 'General timing and all-backend QT boundary verdict disagreement on identical source',
      'input_sha256' => inputs.to_h { |path| [path, TimingAudit.sha256_file(path)] },
      'prior_completion_report_sha256' => TimingAudit.sha256_file(report_path) }
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
    independently of reviewer labels. Do not resolve by majority vote or by
    mechanically requiring MPI_MAX. Conversely, cooperative computation is not
    an independent complete-result replica just because input/result data are
    replicated. Trace root-controlled start dependencies and every path needed
    to produce one complete result, including algorithmic preprocessing and
    completed device work. Explain whether any work after the last collective
    is necessary for that result or only redundant assembly/cleanup. Explicitly
    reconcile the Allgather start-gating and selected-owner membership delivery
    arguments below. If the existing contract/evidence do not settle the case,
    return ambiguous rather than inventing a new policy. No source changes,
    compilation, tool use or execution are permitted.

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
  FileUtils.cp(File.join(campaign, 'verify-audit-completion.rb'), File.join(campaign, 'verify-audit-before-cross-review.rb'))
  FileUtils.cp(__FILE__, campaign)
  phase = 'sol61_same_source_reconciliation'
  checkpoint.call
  TimingAudit::AuditRunner.new(output_dir: output, scope: 'full', jobs: 1, model: 'gpt-6.1-sol', effort: 'xhigh').run
  phase = 'awaiting_overlap_finalization'
  checkpoint.call
rescue Exception => error
  stopped_phase = phase
  phase = 'stopped'
  checkpoint.call('stopped_phase' => stopped_phase, 'error' => "#{error.class}: #{error.message}")
  raise
end
