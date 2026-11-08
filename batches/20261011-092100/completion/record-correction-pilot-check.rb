# frozen_string_literal: true
require_relative 'experiment/tools/timing_audit/lib/timing_audit'

campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
root = '/home/petert/llm_timing_fixes/20261107-fable51-medium-proposals'
gate = JSON.parse(File.read(File.join(campaign, 'correction-pilot-gate.json')))
raise 'Pilot not accepted' unless gate.fetch('passed') && gate.fetch('records') == 16 &&
  gate.fetch('compile_successes') == 16 && gate.fetch('unresolved_ids').empty?
patch = File.join(root, 'materialized/timing-fixes-trial.patch')
inspected_sha = '3133b3712d42355c8c07071a22a4bbb48ce5ee12362efc71c196e468e3f0c277'
raise 'Pilot patch differs from operator inspection' unless TimingAudit.sha256_file(patch) == inspected_sha &&
  inspected_sha == gate.fetch('input_sha256').fetch(patch)
ids = File.readlines(File.join(root, 'trial-ids.txt'), chomp: true).reject(&:empty?)
report = {
  'checked_at' => TimingAudit.utc_now, 'passed' => true, 'ids' => ids,
  'patch_sha256' => inspected_sha, 'patch_lines_read' => 321,
  'inspection' => 'Primary operator read the complete materialized 16-program patch. All edits are to elapsed-time variables, timing-value MPI_MAX collectives, canonical timing output or directly derived throughput. Roomsim hybrid r5 also measures the existing MTJump::init algorithmic RNG preprocessing and includes it in the complete local sum before MPI_MAX. The original preprocessing, self-test, initialization, kernels, result communication and validation remain in place. No benchmark parameters or algorithmic outputs changed.',
  'details' => [
    'Timing reductions use explicit long/MPI_LONG counters on the recorded LP64 target, explicit long long/MPI_LONG_LONG_INT for Black-Scholes microseconds, or double/MPI_DOUBLE for Cahn-Hilliard MPI seconds.',
    'Stencil MPI r2 uses the existing Cartesian communicator and its rank-zero reporter consistently. Other collectives retain the source communicator.',
    'The Roomsim canonical total is the maximum complete per-rank sum of the four measured work phases. Diagnostic stage printouts remain unchanged; input initialization and the existing RNG self-test are not moved into algorithmic timing.',
    'No additional start barriers, work-count changes, algorithm rewrites, CLI changes, build edits or non-timing output changes appear in the patch.'
  ],
  'checks' => { 'all_patch_hunks_inspected' => true,
    'independent_acceptances' => gate.fetch('independent_acceptances'),
    'targeted_adjudications' => gate.fetch('targeted_adjudications'),
    'compile_successes' => 16, 'unresolved' => 0, 'generated_programs_executed_in_review' => 0 },
  'scope' => 'Pilot quality gate only; final native scientific revalidation remains required.'
}
output = File.join(campaign, 'correction-pilot-diff-check.json')
raise 'Quality receipt exists' if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report.reject { |key, _| key == 'ids' })
