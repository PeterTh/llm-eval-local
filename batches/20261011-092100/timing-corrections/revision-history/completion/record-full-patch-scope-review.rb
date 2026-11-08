# frozen_string_literal: true
require_relative 'experiment/tools/timing_audit/lib/timing_audit'
campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
root = '/home/petert/llm_timing_fixes/20261107-fable51-medium-proposals'
id = 'roomsim_claude-fable-5.1-cc-medium_hybrid_r2'
patch = File.join(root, 'materialized/timing-fixes-full.patch')
proposal = File.join(root, 'proposals', id + '.json')
source = File.join(__dir__, 'generated/20261011-092100', id, 'roomsim/roomsim.cpp')
output = File.join(campaign, 'correction-full-operator-scope-review.json')
raise 'Operator scope review already exists' if File.exist?(output)
raise 'Unexpected inspected patch length' unless File.foreach(patch).count == 1381
report = {
  'checked_at' => TimingAudit.utc_now, 'status' => 'one_proposal_requires_scope_revision',
  'all_patch_lines_read' => 1381, 'patch_sha256' => TimingAudit.sha256_file(patch),
  'program_id' => id, 'prior_proposal_sha256' => TimingAudit.sha256_file(proposal),
  'original_source_sha256' => TimingAudit.sha256_file(source),
  'finding' => 'The original initializeSimulation executes RNG polynomial preparation in one of two OpenMP sections, concurrently with mesh/octree initialization (original lines 1296-1316). The proposal removes that section and executes the same work serially in main after initialization. This unnecessarily changes the existing work placement/overlap, contrary to the timing-only requirement to preserve decomposition.',
  'required_revision' => 'Keep the RNG preparation call in its original OpenMP section and preserve both sections. Measure the algorithmic RNG preparation in place using a non-MPI monotonic/chrono timer safe for the executing OpenMP worker; carry only its duration to the canonical total/precomputation accounting and perform the required rank aggregation outside the parallel region. Do not broaden the timer to mesh/octree/input initialization, move computational work, or change algorithmic values, placement, loops, validation or non-timing output.',
  'other_nontrivial_changes_checked' => [
    'N-body hybrid r5 adds an OpenMP barrier after the master start timestamp, gating work on timing only; the existing master block otherwise performs only MPI barrier and timestamp assignment.',
    'QT hybrid r4 moves the start timestamp before the existing world barrier to establish a global makespan. QT hybrid r2 brings its existing setupGpu algorithmic preprocessing inside timing without changing that computation.',
    'Cahn-Hilliard hybrid r1, QT hybrid r3/r5 and Stencil MPI r3 replace ending timing barriers with reductions of completed local durations; independent review must confirm their existing work/device-completion boundaries.',
    'Roomsim hybrid r5 times the existing RNG construction in place; its self-test is const and consumes no reusable algorithmic state. Other Roomsim edits aggregate complete local intervals or phase durations.',
    'The other edits are timing variables, matching MPI duration reductions, reporting and directly derived performance values.'
  ],
  'policy' => 'This concerns the proposed correction, not a newly discovered failure of the original program. Preserve the proposal and all reviews; revise only this correction after the current pass finishes. No source correction commit, native revalidation or performance measurement is authorized by this receipt.',
  'program_executions' => 0
}
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report)
