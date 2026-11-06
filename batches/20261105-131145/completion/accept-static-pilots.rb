# frozen_string_literal: true
require_relative 'observer-pipeline-v3/tools/validation_audit/spmv_native_review'

scratch = __dir__
campaign = '/home/petert/llm_para_campaigns/20261105-131145-terra61-codex-ultra/evaluation'
evidence = File.join(campaign, 'spmv-review')
tool = ValidationAudit::SpmvNativeReview.new(
  workspace: '/tmp/terra61-ultra-spmv-review-20261106-3157415-5hmg8s', evidence: evidence)
proposal = File.join(scratch, 'spmv-luna-pilot-proposal-v2.json')
check = tool.check(proposal)
raise 'Uncertain pilot' unless check.fetch('uncertain_ids').empty?
manual = JSON.parse(File.read(proposal))
ids = %w[cuda hybrid mpi omp].map { |backend| "spmv_gpt-6.1-terra-ultra_#{backend}_r1" }
raise 'Wrong pilot' unless manual.fetch('reviews').map { |row| row.fetch('id') }.sort == ids.sort
root = File.join(evidence, 'spmv-work-count-full')
gate = File.join(root, 'pilot-quality-check.json')
raise 'Pilot already accepted' if File.exist?(gate)
retained = File.join(root, 'delegated-proposals')
FileUtils.mkdir_p(retained)
%w[spmv-luna-pilot-proposal.json spmv-luna-pilot-proposal-v2.json].each do |name|
  target = File.join(retained, name)
  raise 'Proposal already retained' if File.exist?(target)
  FileUtils.cp(File.join(scratch, name), target)
end
quality = {
  'checked_at' => Time.now.utc.iso8601, 'sampled_ids' => ids, 'work_count_disagreement' => false,
  'method' => 'Primary source and compiled-control-flow spot checks of all four pilot programs: parsed iteration bounds; MPI/OpenMP partition coverage; timed host iteration back edges; CUDA/hybrid device launches and device CSR loads/DFMA/back edges. Read the four complete proposals. Confirmed same-input A*x repetition is prescribed by the unchanged sequential reference, not a semantic deviation. Reviewer interval is explicitly an estimated start bound and an observed finish, not measured review time.',
  'source_checks' => { 'cuda' => [[200,230],[283,313]], 'hybrid' => [[216,228],[280,310]], 'mpi' => [[309,323]], 'omp' => [[248,262]] },
  'compiled_checks' => { 'cuda' => { 'host-assembly.txt' => [[1733,1808]], 'device-sass.txt' => [[738,815]] },
    'hybrid' => { 'host-assembly.txt' => [[2150,2188]], 'device-sass.txt' => [[42,104]] },
    'mpi' => { 'host-assembly.txt' => [[2353,2401]] }, 'omp' => { 'host-assembly.txt' => [[949,999]] } }
}
manual['proposal_sha256'] = ValidationAudit.sha(proposal)
manual['primary_quality_check'] = quality
accepted = File.join(root, 'pilot-accepted.json')
ValidationAudit.save(accepted, manual)
tool.record(accepted)
ValidationAudit.save(gate, { 'passed' => true, 'checked_at' => Time.now.utc.iso8601,
  'accepted_sha256' => ValidationAudit.sha(accepted), 'proposal_sha256' => ValidationAudit.sha(proposal),
  'pilot_ids' => ids, 'primary_quality_check' => quality, 'full_delegation_authorized' => true,
  'maximum_parallel_luna_reviewers' => 3, 'program_executions' => 0, 'compilation' => 0,
  'benchmark_runs' => 0, 'program_changes' => 0 })

qt = '/home/petert/llm_timing_audit/20261106-terra61-ultra-codex-qtclustering'
samples = [
  ['cuda_r1', 'valid', [[243,309],[417,430]], 'Distance matrix, candidate kernels, blocking copies and result reconstruction are inside the timed qtClustering call.'],
  ['omp_r1', 'valid', [[130,161],[353,369]], 'Optional input-dependent distance cache construction and the on-demand path are inside the timed call; OpenMP regions join before return.'],
  ['mpi_r4', 'invalid', [[355,385]], 'Root prints its own local interval, while other ranks finalize without a maximum-duration reduction. Timing-only correction required.']
].map do |suffix, verdict, ranges, finding|
  id = 'qtclustering_gpt-6.1-terra-ultra_' + suffix
  result = File.join(qt, 'results', id + '.json')
  raise 'QT pilot changed' unless JSON.parse(File.read(result)).fetch('verdict') == verdict
  source = File.join(scratch, 'generated/20261105-131145', id, 'qtclustering/qtclustering.cpp')
  { 'id' => id, 'result_sha256' => ValidationAudit.sha(result), 'source_sha256' => ValidationAudit.sha(source),
    'ranges' => ranges, 'finding' => finding }
end
ValidationAudit.save(File.join(campaign, 'qt-pilot-source-quality-review.json'), {
  'checked_at' => Time.now.utc.iso8601, 'passed' => true, 'samples' => samples,
  'method' => 'Primary source-grounded usability check of CUDA preprocessing/completion, OpenMP preprocessing boundary and distributed root-local timing; all 16 verdict/category summaries reviewed.',
  'source_commit' => 'e8a5a56facfc3feedc8de8dc0cca41af590acd66',
  'material_disagreement' => false, 'program_executions' => 0, 'compilation' => 0,
  'benchmark_runs' => 0, 'program_changes' => 0 })
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate({ 'spmv_pilot_accepted' => ids, 'qt_pilot_source_quality_passed' => true })
