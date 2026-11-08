# frozen_string_literal: true
$stdout.sync = true
require_relative 'experiment/tools/timing_audit/bin/timing_priority_review'
require 'open3'

campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
primary = '/home/petert/llm_timing_audit/20261107-fable51-medium'
output = primary + '-platform-sol61'
proof_root = File.join(campaign, 'cholesky-mpi-r2-topology-context')
proof = JSON.parse(File.read(File.join(proof_root, 'preprocessing-proof.json')))
id = proof.fetch('program_id')
raise 'Wrong platform follow-up scope' unless id == 'cholesky_claude-fable-5.1-cc-medium_mpi_r2'
ids = [id, 'cholesky_claude-fable-5.1-cc-medium_mpi_r5']
state, status = Open3.capture2('systemctl', '--user', 'show', 'llm-fable51-medium-timing-full-20261107.service', '--property=ActiveState', '--value')
raise 'Main two-worker review pass still active' unless status.success? && !%w[active activating deactivating].include?(state.strip)
raise 'Main audit did not finish normally' unless JSON.parse(File.read(File.join(campaign, 'audit-full-progress.json'))).fetch('phase') == 'awaiting_correction_review'
prior_paths = ids.to_h { |selected| [selected, File.join(primary + '-sol61', 'results', selected + '.json')] }
prior_paths.each_value do |path|
  prior = JSON.parse(File.read(path))
  raise 'Case no longer needs uncertainty review' unless prior.fetch('verdict') == 'ambiguous' || prior.fetch('confidence') != 'high'
end
context = File.join(proof_root, 'platform-context.txt')
raise 'Context proof changed' unless TimingAudit.sha256_file(context) == proof.fetch('context_sha256') &&
  proof.fetch('program_executions').zero? && proof.fetch('source_changes').zero?
raise 'Original reviewed source changed' unless TimingAudit.sha256_file(File.join(__dir__, 'generated/20261011-092100', id, 'cholesky/cholesky.cpp')) == proof.fetch('source_sha256')
unless File.exist?(output)
  selection = File.join(proof_root, 'selection.jsonl')
  rows = ids.map do |selected|
    { 'program_id' => selected,
      'reason' => selected == id ?
        'The Sol adjudicator explicitly left the startup-dependency proof unresolved because communicator membership was absent. Exact native-flag preprocessing resolves the selected branch; a targeted blind follow-up receives this additional static platform evidence.' :
        'The Sol adjudicator accepted the constructor-based timing proof only at medium confidence. Additional single-host target-placement evidence establishes the scope of MPI_COMM_TYPE_SHARED; recheck the source-grounded constructor/shared-window dependency without treating every collective as a barrier.',
      'prior_response_sha256' => TimingAudit.sha256_file(prior_paths.fetch(selected)),
      'preprocessing_proof_sha256' => TimingAudit.sha256_file(File.join(proof_root, 'preprocessing-proof.json')) }
  end
  TimingAudit.atomic_write(selection, TimingAudit.dump_jsonl(rows))
  TimingPriorityReview.prepare_supplemental(main_root: primary, output_dir: output,
    selection_path: selection, context_path: context, model: 'gpt-6.1-sol')
  prior_paths.each do |selected, path|
    FileUtils.cp(path, File.join(output, "prior-uncertain-review-#{selected}.json"))
  end
  FileUtils.cp(File.join(proof_root, 'preprocessing-proof.json'), File.join(output, 'preprocessing-proof.json'))
end
selection = TimingAudit.load_jsonl(File.join(output, 'supplemental-selection.jsonl'))
raise 'Follow-up selection changed' unless selection.map { |row| row.fetch('program_id') } == ids
selection.each do |row|
  raise 'Follow-up inputs changed' unless row.fetch('prior_response_sha256') == TimingAudit.sha256_file(prior_paths.fetch(row.fetch('program_id'))) &&
    row.fetch('preprocessing_proof_sha256') == TimingAudit.sha256_file(File.join(proof_root, 'preprocessing-proof.json'))
end
FileUtils.cp(__FILE__, campaign)
TimingAudit::AuditRunner.new(output_dir: output, scope: 'full', jobs: 2, model: 'gpt-6.1-sol', effort: 'xhigh').run
TimingAudit::AuditVerifier.new(output, 'full').run
puts 'Targeted static platform review complete; no original review, source or final decision changed.'
