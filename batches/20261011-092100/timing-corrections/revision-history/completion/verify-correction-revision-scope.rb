# frozen_string_literal: true
require_relative 'experiment/tools/timing_audit/lib/timing_fix_review'
require_relative 'experiment/tools/timing_audit/lib/timing_fix_adjudication'

campaign = '/home/petert/llm_para_campaigns/20261011-092100-fable51-medium/evaluation'
gate_path = File.join(campaign, 'correction-revision-1.json')
gate = JSON.parse(File.read(gate_path))
id = 'roomsim_claude-fable-5.1-cc-medium_hybrid_r2'
raise 'Revision incomplete' unless gate.fetch('passed') && gate.fetch('accepted_corrections') == 69 &&
  gate.fetch('program_id') == id && gate.fetch('prior_evidence_unchanged') && gate.fetch('reused_independent_reviews') == 68
old = gate.fetch('prior_roots')
current = gate.fetch('evidence_roots')
patches = [old, current].map { |roots| File.join(roots.fetch('proposals'), 'materialized/timing-fixes-full.patch') }
inspected_sha = '23b915cb9957ea87c3148f459f500297b77b1d5868adb91db95974c61ee96ad0'
raise 'Inspected revised patch changed' unless TimingAudit.sha256_file(patches.last) == inspected_sha
scope = JSON.parse(File.read(File.join(campaign, 'correction-full-operator-scope-review.json')))
raise 'Original patch scope binding changed' unless TimingAudit.sha256_file(patches.first) == scope.fetch('patch_sha256')
parts = patches.map { |path| File.read(path).split(/(?=^diff --git )/).reject(&:empty?).to_h { |part| [part.lines.first, part] } }
raise 'Patch path coverage changed' unless parts.first.keys == parts.last.keys && parts.last.size == 69
changed = parts.first.keys.reject { |key| parts.first.fetch(key) == parts.last.fetch(key) }
raise 'Unrelated patch changed' unless changed.size == 1 && changed.first.include?("/#{id}/roomsim/roomsim.cpp ")
fingerprints = old.values.flat_map { |root| Dir[File.join(root, '**', '*')].select { |path| File.file?(path) } }.sort.to_h do |path|
  raise 'Symlink in prior evidence' if File.symlink?(path)
  [path, TimingAudit.sha256_file(path)]
end
raise 'Prior evidence changed' unless Digest::SHA256.hexdigest(JSON.generate(fingerprints)) == gate.fetch('prior_evidence_tree_sha256')
TimingFix::ProposalVerifier.new(current.fetch('proposals'), 'full').run
TimingFixReview::Verifier.new(current.fetch('review'), 'full').run
TimingFixAdjudication::Verifier.new(current.fetch('adjudication'), 'full').run
reviews = TimingAudit.load_jsonl(File.join(current.fetch('review'), 'summary-full.jsonl')).to_h { |row| [row.fetch('program_id'), row] }
adjudications = TimingAudit.load_jsonl(File.join(current.fetch('adjudication'), 'summary-full.jsonl')).to_h { |row| [row.fetch('program_id'), row] }
raise 'Review count changed' unless reviews.size == 69
reviews.each do |key, review|
  decision = adjudications[key] || review
  raise "Unaccepted correction #{key}" unless (decision['final_verdict'] || decision.fetch('verdict')) == 'accept' && decision.fetch('confidence') == 'high'
end
raise 'No independent acceptance of revised Roomsim' unless reviews.fetch(id).fetch('verdict') == 'accept' && reviews.fetch(id).fetch('confidence') == 'high'
compile = YAML.safe_load_file(File.join(current.fetch('proposals'), 'materialized/summary-full.yaml'))
raise 'Compile gate failed' unless compile.fetch('compile_successes') == 69 && compile.fetch('compile_failures').empty? && compile.fetch('patch_sha256') == inspected_sha
report = {
  'checked_at' => TimingAudit.utc_now, 'passed' => true, 'program_id' => id,
  'revision_gate_sha256' => TimingAudit.sha256_file(gate_path), 'patch_sha256' => inspected_sha,
  'old_patch_lines_read' => scope.fetch('all_patch_lines_read'),
  'revised_patch_lines' => File.foreach(patches.last).count,
  'revised_section_lines_read' => parts.last.fetch(changed.first).lines.size,
  'unchanged_patch_sections' => 68, 'all_source_patch_hunks_checked' => true,
  'scope_resolution' => 'Roomsim preserves both original OpenMP sections and the RNG preparation call in its original section. A steady_clock timer records only that call; its duration is consumed after the existing implicit OpenMP completion barrier. It is added to local precomputation before MPI_MAX outside the parallel region. The other edits only reduce completed phase timings; canonical total and derived throughput consume these values. No algorithmic call, concurrency decomposition, workload, validation or non-timing output is changed.',
  'accepted_corrections' => 69, 'compile_successes' => 69,
  'independent_review_counts' => reviews.values.map { |row| row.fetch('verdict') }.tally,
  'targeted_adjudications' => adjudications.size, 'prior_evidence_unchanged' => true,
  'program_executions_in_review' => 0, 'next_gate' => 'one source commit followed by native scientific revalidation of these 69 programs'
}
output = File.join(campaign, 'correction-revision-diff-check.json')
raise 'Revision scope receipt exists' if File.exist?(output)
TimingAudit.atomic_write(output, JSON.pretty_generate(report) + "\n")
FileUtils.cp(__FILE__, campaign)
puts JSON.pretty_generate(report)
